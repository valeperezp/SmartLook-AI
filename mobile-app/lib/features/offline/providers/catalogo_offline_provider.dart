import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/schema.dart';
import '../data/catalogo_local_dao.dart';
import '../data/mock_data.dart';
import '../data/sync_queue_dao.dart';
import '../models/catalogo_item.dart';
import '../services/catalogo_sync_service.dart';

/// Catálogo offline del cliente (CU8) y reserva local de un producto (CU9).
class CatalogoOfflineProvider extends ChangeNotifier {
  CatalogoOfflineProvider({CatalogoLocalDao? catalogoDao, SyncQueueDao? colaDao, CatalogoSyncService? catalogoSync})
      : _catalogoDao = catalogoDao ?? CatalogoLocalDao(),
        _colaDao = colaDao ?? SyncQueueDao(),
        _catalogoSyncInyectado = catalogoSync;

  final CatalogoLocalDao _catalogoDao;
  final SyncQueueDao _colaDao;
  final CatalogoSyncService? _catalogoSyncInyectado;
  late final CatalogoSyncService _catalogoSync = _catalogoSyncInyectado ?? CatalogoSyncService(dao: _catalogoDao);
  static const _uuid = Uuid();

  List<CatalogoItem> _productos = const [];
  int _pendientes = 0;
  bool _cargando = false;
  String? _error;
  String? _ultimoMensaje;
  final Set<int> _reservando = {};

  List<CatalogoItem> get productos => _productos;
  int get pendientes => _pendientes;
  bool get cargando => _cargando;
  String? get error => _error;

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
      _ultimoMensaje = CatalogoSyncService.mensajeDescarga(resultado: r, pendientes: _pendientes);
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

  Future<void> _leer() async {
    final filas = await _catalogoDao.obtenerProductos();
    final pendientes = await _colaDao.obtenerOperacionesPendientes();
    _productos = filas.map(CatalogoItem.fromMap).toList(growable: false);
    _pendientes = pendientes.length;
  }
}
