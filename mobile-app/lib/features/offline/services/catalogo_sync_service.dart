import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/models/disponibilidad.dart';
import '../../../core/models/producto.dart';
import '../../../core/services/catalogo_service.dart';
import '../data/catalogo_local_dao.dart';

/// No hubo red (o el servidor no respondió a tiempo): el catálogo local se conserva tal cual.
class SinConexionException implements Exception {
  @override
  String toString() => 'Sin conexión con el servidor.';
}

/// Resultado de una descarga: cuántas variantes quedaron guardadas y qué avisos de stock (CU16) se activaron.
class ResultadoDescargaCatalogo {
  const ResultadoDescargaCatalogo({required this.registros, this.avisos = const []});

  final int registros;
  final List<Map<String, dynamic>> avisos;
}

/// Descarga el catálogo real del backend y lo guarda en SQLite (sustituye al catálogo de prueba).
///
/// El backend no tiene un endpoint de sincronización de catálogo: se arma con los endpoints públicos
/// `GET /catalogo/productos` y `GET /catalogo/productos/{id}/disponibilidad` (stock por sucursal, talla y color).
/// No usa `/inventario/*` porque solo lo pueden llamar administradores y encargados, y el catálogo offline
/// lo usan también clientes y cajeros.
class CatalogoSyncService {
  CatalogoSyncService({CatalogoService? catalogoService, CatalogoLocalDao? dao})
      : _catalogo = catalogoService ?? CatalogoService(),
        _dao = dao ?? CatalogoLocalDao();

  final CatalogoService _catalogo;
  final CatalogoLocalDao _dao;

  /// Cuántas disponibilidades se piden a la vez (una por producto).
  static const _paralelismo = 6;

  /// Descarga el catálogo de [sucursalId] (o de todas las sucursales si es null) y reemplaza el local.
  ///
  /// - Si falla la red lanza [SinConexionException] y el catálogo local no se toca.
  /// - Si el servidor no devuelve ninguna variante no se guarda nada (así una respuesta vacía no borra lo que sirve).
  Future<ResultadoDescargaCatalogo> descargarCatalogoDesdeServidor({int? sucursalId}) async {
    try {
      final productos = (await _catalogo.listarProductos()).where((p) => p.activo).toList();
      final disponibilidades = <ProductoDisponibilidad>[];
      for (var i = 0; i < productos.length; i += _paralelismo) {
        final tanda = productos.skip(i).take(_paralelismo);
        disponibilidades.addAll(await Future.wait(tanda.map((p) => _catalogo.obtenerDisponibilidad(p.id))));
      }

      final filas = construirFilas(productos, disponibilidades, sucursalId: sucursalId);
      final avisos = await _dao.guardarLoteCatalogo(filas);
      return ResultadoDescargaCatalogo(registros: filas.length, avisos: avisos);
    } on DioException catch (e) {
      if (_esProblemaDeRed(e)) throw SinConexionException();
      rethrow;
    }
  }

  /// Texto para el usuario según lo que pasó en la descarga (éxito o el error capturado).
  static String mensajeDescarga({ResultadoDescargaCatalogo? resultado, Object? error, int pendientes = 0}) {
    if (error is SinConexionException) return 'Sin conexión, usando catálogo local';
    if (error != null) return 'No se pudo actualizar el catálogo. Se mantiene el catálogo local.';
    final registros = resultado?.registros ?? 0;
    if (registros == 0) return 'El servidor no devolvió productos. Se mantiene el catálogo local.';
    final base = 'Catálogo actualizado: $registros ${registros == 1 ? "variante" : "variantes"}.';
    return pendientes > 0 ? '$base Hay $pendientes operación(es) sin sincronizar: su stock se descuenta al sincronizar.' : base;
  }

  static bool _esProblemaDeRed(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return true;
      default:
        return e.response == null; // sin respuesta del servidor
    }
  }

  /// Convierte la respuesta del backend en filas de `catalogo_local` (una por producto + talla + color + sucursal).
  @visibleForTesting
  static List<Map<String, dynamic>> construirFilas(
    List<Producto> productos,
    List<ProductoDisponibilidad> disponibilidades, {
    int? sucursalId,
  }) {
    final porProducto = {for (final p in productos) p.id: p};
    final filas = <int, Map<String, dynamic>>{};
    for (final d in disponibilidades) {
      final producto = porProducto[d.productoId];
      if (producto == null) continue;
      for (final suc in d.disponibilidad) {
        if (sucursalId != null && suc.sucursalId != sucursalId) continue;
        for (final item in suc.items) {
          final id = claveLocal(suc.sucursalId, d.productoId, item.tallaId, item.colorId);
          filas[id] = {
            'inventario_id': id,
            'sucursal_id': suc.sucursalId,
            'producto_id': d.productoId,
            'talla_id': item.tallaId,
            'color_id': item.colorId,
            'nombre_producto': producto.nombre,
            'nombre_talla': item.nombreTalla,
            'nombre_color': item.nombreColor,
            'precio_centavos': (producto.precio * 100).round(),
            'imagen_url': producto.imagenUrl,
            'cantidad_disponible': item.cantidadDisponible < 0 ? 0 : item.cantidadDisponible,
            'activo': 1,
          };
        }
      }
    }
    return filas.values.toList(growable: false);
  }

  /// Clave local de la variante. El endpoint de disponibilidad no devuelve el id de inventario del servidor, y
  /// `inventario_id` solo sirve como clave primaria local (las operaciones se envían con producto, talla y color).
  /// Se arma de forma estable: sucursal < 10^5 productos < 10^4 tallas < 10^4 colores.
  @visibleForTesting
  static int claveLocal(int sucursalId, int productoId, int? tallaId, int? colorId) =>
      ((sucursalId * 100000 + productoId) * 10000 + (tallaId ?? 0)) * 10000 + (colorId ?? 0);
}
