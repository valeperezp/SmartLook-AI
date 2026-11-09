import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/schema.dart';
import '../data/catalogo_local_dao.dart';
import '../data/mock_data.dart';
import '../data/qr_devolucion_dao.dart';
import '../data/sync_queue_dao.dart';
import '../models/catalogo_item.dart';
import '../services/catalogo_sync_service.dart';
import '../services/qr_sucursal_cache.dart';

/// Pasadas estas horas sin descargar el catálogo, se avisa que la información puede estar desactualizada (CU8).
const Duration limiteCatalogoDesactualizado = Duration(hours: 24);

/// Catálogo offline del cliente (CU8) y reserva local de un producto (CU9).
class CatalogoOfflineProvider extends ChangeNotifier {
  CatalogoOfflineProvider({
    CatalogoLocalDao? catalogoDao,
    SyncQueueDao? colaDao,
    CatalogoSyncService? catalogoSync,
    QrSucursalCache? qrCache,
    DateTime Function()? ahora,
  })  : _catalogoDao = catalogoDao ?? CatalogoLocalDao(),
        _colaDao = colaDao ?? SyncQueueDao(),
        _catalogoSyncInyectado = catalogoSync,
        // ignore: prefer_initializing_formals
        _qrCache = qrCache,
        _ahora = ahora ?? DateTime.now;

  final CatalogoLocalDao _catalogoDao;
  final SyncQueueDao _colaDao;
  final CatalogoSyncService? _catalogoSyncInyectado;

  /// Copia local del QR bancario de cada sucursal (null = no se guarda; así las pruebas no salen a la red).
  final QrSucursalCache? _qrCache;
  final DateTime Function() _ahora;
  late final CatalogoSyncService _catalogoSync = _catalogoSyncInyectado ?? CatalogoSyncService(dao: _catalogoDao);
  static const _uuid = Uuid();

  List<CatalogoItem> _productos = const [];
  int _pendientes = 0;
  bool _cargando = false;
  String? _error;
  String? _ultimoMensaje;
  DateTime? _descargadoEn;
  final Set<int> _reservando = {};

  List<CatalogoItem> get productos => _productos;
  int get pendientes => _pendientes;
  bool get cargando => _cargando;
  String? get error => _error;

  /// Cuándo se descargó el catálogo que se está mostrando (null si no hay catálogo guardado).
  DateTime? get descargadoEn => _descargadoEn;

  /// Hace cuánto se descargó el catálogo (null si no hay catálogo).
  Duration? get antiguedad => _descargadoEn == null ? null : _ahora().difference(_descargadoEn!);

  /// El catálogo tiene más de 24 horas sin actualizarse: la pantalla muestra "Información desactualizada".
  bool get desactualizado => estaDesactualizado(_descargadoEn, _ahora());

  /// `ahora - fechaDescarga > 24 h`. Sin catálogo (fecha nula) o con una fecha futura (reloj desajustado) no hay aviso.
  static bool estaDesactualizado(DateTime? fechaDescarga, DateTime ahora) {
    if (fechaDescarga == null) return false;
    return ahora.difference(fechaDescarga) > limiteCatalogoDesactualizado;
  }

  /// Resultado legible de la última acción (reserva, carga de datos de prueba) para mostrar en un SnackBar.
  String? get ultimoMensaje => _ultimoMensaje;

  bool get soportado => AppDatabase.soportado;

  bool estaReservando(CatalogoItem p) => _reservando.contains(p.inventarioId);

  /// Lee el catálogo y el número de operaciones pendientes desde SQLite.
  Future<void> cargar() async {
    if (!soportado) {
      _error = 'El modo offline no está disponible en web.';
      notifyListeners();
      return;
    }
    _cargando = true;
    _error = null;
    notifyListeners();
    try {
      await _leer();
    } catch (e, st) {
      debugPrint('[CatalogoOfflineProvider] Error al cargar el catálogo local: $e\n$st');
      _error = 'No se pudo leer el catálogo local.';
    } finally {
      _cargando = false;
      notifyListeners();
    }
  }

  /// Carga las 10 prendas falsas (solo debug) y refresca la lista. Con [reponerAgotados] las agotadas llegan con
  /// stock (simula la llegada de mercadería para probar los avisos de "Avísame cuando llegue").
  Future<void> cargarDatosMock({bool reponerAgotados = false}) async {
    try {
      await cargarCatalogoMock(dao: _catalogoDao, reponerAgotados: reponerAgotados);
      _ultimoMensaje = kDebugMode
          ? (reponerAgotados ? 'Llegó mercadería (simulado).' : 'Datos de prueba cargados.')
          : 'Los datos de prueba solo se cargan en modo debug.';
    } catch (e) {
      _ultimoMensaje = 'No se pudieron cargar los datos de prueba.';
    }
    await cargar();
  }

  /// Descarga el catálogo real del backend (todas las sucursales) y reemplaza el local, incluidos los datos de prueba.
  /// Sin red conserva el catálogo local. Devuelve los avisos de stock (CU16) que se activaron.
  Future<List<Map<String, dynamic>>> actualizarDesdeServidor() async {
    if (!soportado) {
      _ultimoMensaje = 'El modo offline no está disponible en web.';
      notifyListeners();
      return const [];
    }
    _cargando = true;
    _error = null;
    notifyListeners();
    var avisos = const <Map<String, dynamic>>[];
    try {
      final r = await _catalogoSync.descargarCatalogoDesdeServidor();
      avisos = r.avisos;
      await _leer();
      final avisoQr = await _guardarQrDeSucursales();
      _ultimoMensaje = CatalogoSyncService.mensajeDescarga(resultado: r, pendientes: _pendientes) + (avisoQr == null ? '' : ' $avisoQr');
    } catch (e, st) {
      if (e is! SinConexionException) debugPrint('[CatalogoOfflineProvider] Error al descargar el catálogo: $e\n$st');
      _ultimoMensaje = CatalogoSyncService.mensajeDescarga(error: e);
    } finally {
      _cargando = false;
      notifyListeners();
    }
    return avisos;
  }

  /// Reserva 1 unidad de [producto] sin conexión: guarda la operación RESERVA_CLIENTE en la cola y
  /// descuenta 1 del stock local (descuento optimista) en la misma transacción. Devuelve si se guardó.
  Future<bool> reservarProducto(CatalogoItem producto, int clienteId) async {
    if (_reservando.contains(producto.inventarioId)) return false; // doble toque
    if (!producto.hayStock) {
      _ultimoMensaje = 'Sin stock disponible.';
      notifyListeners();
      return false;
    }

    _reservando.add(producto.inventarioId);
    notifyListeners();
    var guardada = false;
    try {
      await _colaDao.guardarOperacionOffline(
        {
          'sucursal_id': producto.sucursalId,
          'items': [
            {
              'inventario_id': producto.inventarioId,
              'producto_id': producto.productoId,
              'talla_id': producto.tallaId,
              'color_id': producto.colorId,
              'nombre_producto': producto.nombre,
              'cantidad': 1,
              'precio_unitario_centavos': producto.precioCentavos,
            },
          ],
        },
        _uuid.v4(),
        Schema.tipoReservaCliente,
        clienteId,
        descontarStockLocal: true,
      );
      guardada = true;
      _ultimoMensaje = 'Reserva guardada en el dispositivo. Se enviará al recuperar la conexión.';
    } on StockLocalInsuficiente {
      _ultimoMensaje = 'Ya no queda stock disponible de este producto.';
    } catch (e, st) {
      debugPrint('[CatalogoOfflineProvider] Error al guardar la reserva offline: $e\n$st');
      _ultimoMensaje = 'No se pudo guardar la reserva.';
    } finally {
      _reservando.remove(producto.inventarioId);
    }

    try {
      await _leer(); // refleja el stock descontado (o el real, si la reserva falló)
    } catch (e) {
      debugPrint('[CatalogoOfflineProvider] Error al refrescar tras reservar: $e');
    }
    notifyListeners();
    return guardada;
  }

  /// Por qué NO hay QR guardado de cada sucursal (la sucursal no tiene QR configurado, la imagen no está en el servidor...). Una
  /// sucursal cuyo QR se guardó bien no aparece. Se muestra en la hoja de compra para que el cliente sepa qué pasó.
  final Map<int, String> _motivosSinQr = {};

  String? motivoSinQr(int sucursalId) => _motivosSinQr[sucursalId];

  /// Con red: guarda en el celular el QR bancario de cada sucursal del catálogo para poder cobrar compras offline. Nunca falla.
  /// Devuelve un aviso para el usuario si algún QR NO se pudo descargar (así el fallo no queda oculto), o null si todo salió bien.
  Future<String?> _guardarQrDeSucursales() async {
    final cache = _qrCache;
    if (cache == null) return null;
    try {
      final r = await cache.actualizarConDetalle({for (final p in _productos) p.sucursalId});
      for (final id in r.guardadas) {
        _motivosSinQr.remove(id);
      }
      for (final id in [...r.sinQr, ...r.fallidas.keys]) {
        final motivo = r.motivoDe(id);
        if (motivo != null) _motivosSinQr[id] = motivo;
      }
      if (r.fallidas.isEmpty) return null;
      return r.fallidas.entries.map((e) => 'No se pudo descargar el QR de la sucursal ${e.key}: ${e.value}.').join(' ');
    } catch (e) {
      debugPrint('[CatalogoOfflineProvider] No se pudo guardar el QR de las sucursales: $e');
      return null;
    }
  }

  /// La imagen guardada del QR bancario de [sucursalId] (null si nunca se descargó): se muestra sin conexión al pagar.
  Future<Uint8List?> qrDeSucursal(int sucursalId) async => _qrCache?.obtener(sucursalId);

  /// Compra [cantidad] unidades de [producto] SIN conexión, pagadas por QR: guarda en la cola una VENTA_CLIENTE_QR con el
  /// comprobante de la transferencia ([comprobante], en base64) y baja el stock local enseguida (descuento optimista). El stock
  /// real solo baja cuando el encargado aprueba el pago. Devuelve si se guardó; el motivo queda en [ultimoMensaje].
  Future<bool> comprarConQr(
    CatalogoItem producto,
    int clienteId, {
    required int cantidad,
    required List<int> comprobante,
    String nombreComprobante = 'comprobante.jpg',
  }) async {
    if (_reservando.contains(producto.inventarioId)) return false; // doble toque
    if (cantidad < 1 || cantidad > producto.cantidadDisponible) {
      _ultimoMensaje = producto.hayStock ? 'Solo quedan ${producto.cantidadDisponible} unidad(es) disponibles.' : 'Sin stock disponible.';
      notifyListeners();
      return false;
    }
    try {
      QrDevolucionDao.validarImagen(comprobante); // mismas reglas que el servidor: PNG/JPG/WEBP de hasta 5 MB
    } on QrInvalido catch (e) {
      _ultimoMensaje = 'El comprobante no sirve: ${e.mensaje}';
      notifyListeners();
      return false;
    }

    _reservando.add(producto.inventarioId);
    notifyListeners();
    var guardada = false;
    try {
      await _colaDao.guardarOperacionOffline(
        {
          'sucursal_id': producto.sucursalId,
          'items': [
            {
              'inventario_id': producto.inventarioId,
              'producto_id': producto.productoId,
              'talla_id': producto.tallaId,
              'color_id': producto.colorId,
              'nombre_producto': producto.nombre,
              'cantidad': cantidad,
              'precio_unitario_centavos': producto.precioCentavos,
            },
          ],
          'comprobante_base64': base64Encode(comprobante),
          'comprobante_nombre': nombreComprobante,
        },
        _uuid.v4(),
        Schema.tipoVentaClienteQr,
        clienteId,
        descontarStockLocal: true,
      );
      guardada = true;
      _ultimoMensaje = 'Compra guardada en el dispositivo. Se enviará al recuperar la conexión y el encargado verificará tu comprobante.';
    } on StockLocalInsuficiente {
      _ultimoMensaje = 'Ya no queda stock disponible de este producto.';
    } catch (e, st) {
      debugPrint('[CatalogoOfflineProvider] Error al guardar la compra offline: $e\n$st');
      _ultimoMensaje = 'No se pudo guardar la compra.';
    } finally {
      _reservando.remove(producto.inventarioId);
    }

    try {
      await _leer(); // refleja el stock descontado (o el real, si la compra falló)
    } catch (e) {
      debugPrint('[CatalogoOfflineProvider] Error al refrescar tras comprar: $e');
    }
    notifyListeners();
    return guardada;
  }

  Future<void> _leer() async {
    final filas = await _catalogoDao.obtenerProductos();
    final pendientes = await _colaDao.obtenerOperacionesPendientes();
    _productos = filas.map(CatalogoItem.fromMap).toList(growable: false);
    _pendientes = pendientes.length;
    _descargadoEn = filas.isEmpty ? null : await _catalogoDao.obtenerFechaUltimaDescarga();
  }
}
