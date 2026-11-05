import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/offline_config.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/schema.dart';
import '../data/catalogo_local_dao.dart';
import '../data/mock_data.dart';
import '../data/sync_queue_dao.dart';
import '../data/turno_caja_dao.dart';
import '../models/catalogo_item.dart';
import '../services/catalogo_sync_service.dart';

/// Una línea del carrito de venta: un producto (variante) y cuántas unidades se llevan.
class LineaVenta {
  LineaVenta(this.producto, this.cantidad);

  final CatalogoItem producto;
  int cantidad;

  int get subtotalCentavos => producto.precioCentavos * cantidad;
}

/// Punto de venta offline del cajero (CU10): arma el carrito y registra la venta de contado en SQLite.
class VentaOfflineProvider extends ChangeNotifier {
  VentaOfflineProvider({CatalogoLocalDao? catalogoDao, SyncQueueDao? colaDao, CatalogoSyncService? catalogoSync})
      : _catalogoDao = catalogoDao ?? CatalogoLocalDao(),
        _colaDao = colaDao ?? SyncQueueDao(),
        _catalogoSyncInyectado = catalogoSync;

  final CatalogoLocalDao _catalogoDao;
  final SyncQueueDao _colaDao;
  final CatalogoSyncService? _catalogoSyncInyectado;
  late final CatalogoSyncService _catalogoSync = _catalogoSyncInyectado ?? CatalogoSyncService(dao: _catalogoDao);
  static const _uuid = Uuid();

  List<CatalogoItem> _productos = const [];
  final List<LineaVenta> _lineas = [];
  bool _cargando = false;
  bool _procesando = false;
  String? _error;
  String? _ultimoMensaje;
  int _puntosUltimaVenta = 0;

  List<CatalogoItem> get productos => _productos;
  List<LineaVenta> get lineas => List.unmodifiable(_lineas);
  bool get cargando => _cargando;
  bool get procesando => _procesando;
  String? get error => _error;

  /// Resultado legible de la última acción, para mostrar en un SnackBar.
  String? get ultimoMensaje => _ultimoMensaje;

  bool get soportado => AppDatabase.soportado;

  /// Puntos que se acreditaron al cliente en la última venta guardada (0 si no hubo cliente).
  int get puntosUltimaVenta => _puntosUltimaVenta;
  bool get carritoVacio => _lineas.isEmpty;
  int get unidadesEnCarrito => _lineas.fold(0, (suma, l) => suma + l.cantidad);

  // ---------------------------------------------------------------------------
  // Catálogo local
  // ---------------------------------------------------------------------------

  /// Lee de SQLite el catálogo de [sucursalId].
  Future<void> cargar(int sucursalId) async {
    if (!soportado) {
      _error = 'El modo offline no está disponible en web.';
      notifyListeners();
      return;
    }
    _cargando = true;
    _error = null;
    notifyListeners();
    try {
      await _leer(sucursalId);
    } catch (e, st) {
      debugPrint('[VentaOfflineProvider] Error al cargar el catálogo local: $e\n$st');
      _error = 'No se pudo leer el catálogo local.';
    } finally {
      _cargando = false;
      notifyListeners();
    }
  }

  /// Carga las 10 prendas falsas (solo debug) para [sucursalId] y refresca la lista.
  Future<void> cargarDatosMock(int sucursalId) async {
    try {
      await cargarCatalogoMock(sucursalId: sucursalId, dao: _catalogoDao);
      _ultimoMensaje = kDebugMode ? 'Datos de prueba cargados.' : 'Los datos de prueba solo se cargan en modo debug.';
    } catch (e) {
      _ultimoMensaje = 'No se pudieron cargar los datos de prueba.';
    }
    _lineas.clear(); // el catálogo se reemplazó: las líneas viejas ya no corresponden
    await cargar(sucursalId);
  }

  /// Descarga el catálogo real de [sucursalId] desde el backend y reemplaza el local (incluidos los datos de prueba).
  /// Sin red conserva el catálogo local.
  Future<void> actualizarDesdeServidor(int sucursalId) async {
    if (!soportado) {
      _ultimoMensaje = 'El modo offline no está disponible en web.';
      notifyListeners();
      return;
    }
    _cargando = true;
    _error = null;
    notifyListeners();
    try {
      final r = await _catalogoSync.descargarCatalogoDesdeServidor(sucursalId: sucursalId);
      _lineas.clear(); // el catálogo se reemplazó: las líneas viejas ya no corresponden
      await _leer(sucursalId);
      final pendientes = (await _colaDao.obtenerOperacionesPendientes()).length;
      _ultimoMensaje = CatalogoSyncService.mensajeDescarga(resultado: r, pendientes: pendientes);
    } catch (e, st) {
      if (e is! SinConexionException) debugPrint('[VentaOfflineProvider] Error al descargar el catálogo: $e\n$st');
      _ultimoMensaje = CatalogoSyncService.mensajeDescarga(error: e);
    } finally {
      _cargando = false;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Carrito
  // ---------------------------------------------------------------------------

  int cantidadEnCarrito(CatalogoItem producto) {
    for (final l in _lineas) {
      if (l.producto.inventarioId == producto.inventarioId) return l.cantidad;
    }
    return 0;
  }

  /// Unidades que todavía se pueden agregar al carrito (stock local menos lo ya agregado).
  int disponibleParaAgregar(CatalogoItem producto) => producto.cantidadDisponible - cantidadEnCarrito(producto);

  /// Agrega 1 unidad. Devuelve `false` (y deja un mensaje) si no hay más stock local.
  bool agregarProducto(CatalogoItem producto) {
    if (_procesando) return false;
    if (disponibleParaAgregar(producto) <= 0) {
      _ultimoMensaje = 'No hay más stock de "${producto.nombre}".';
      notifyListeners();
      return false;
    }
    final i = _lineas.indexWhere((l) => l.producto.inventarioId == producto.inventarioId);
    if (i >= 0) {
      _lineas[i].cantidad++;
    } else {
      _lineas.add(LineaVenta(producto, 1));
    }
    notifyListeners();
    return true;
  }

  /// Quita 1 unidad (o la línea completa con [todo]).
  void quitarProducto(CatalogoItem producto, {bool todo = false}) {
    if (_procesando) return;
    final i = _lineas.indexWhere((l) => l.producto.inventarioId == producto.inventarioId);
    if (i < 0) return;
    if (todo || _lineas[i].cantidad <= 1) {
      _lineas.removeAt(i);
    } else {
      _lineas[i].cantidad--;
    }
    notifyListeners();
  }

  /// Total del carrito en centavos.
  int calcularTotal() => _lineas.fold(0, (suma, l) => suma + l.subtotalCentavos);

  void limpiarCarrito() {
    if (_procesando) return;
    _lineas.clear();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Cobro
  // ---------------------------------------------------------------------------

  /// Convierte un monto escrito por el usuario ("20", "20.5", "20,50") a centavos; `null` si no es válido.
  static int? parseMonto(String texto) {
    final m = RegExp(r'^(\d+)(?:[.,](\d{1,2}))?$').firstMatch(texto.trim());
    if (m == null) return null;
    final enteros = int.parse(m.group(1)!);
    final decimales = int.parse((m.group(2) ?? '').padRight(2, '0'));
    return enteros * 100 + decimales;
  }

  /// Registra la venta de contado: guarda cabecera + ítems + cola y descuenta el stock local de cada
  /// ítem, todo en una transacción. Si [montoRecibidoCentavos] viene, debe cubrir el total.
  /// Devuelve `true` si se guardó (y vacía el carrito).
  ///
  /// [turnoUuid] es el turno de caja abierto al que se vincula la venta (el arqueo la suma al monto esperado).
  /// [clienteId] (opcional) es el cliente registrado al que se le acreditan los puntos de fidelización.
  Future<bool> procesarVenta({
    required int cajeroId,
    required int sucursalId,
    int? montoRecibidoCentavos,
    String? turnoUuid,
    int? clienteId,
  }) async {
    if (_procesando) return false;
    if (_lineas.isEmpty) {
      _ultimoMensaje = 'El carrito está vacío.';
      notifyListeners();
      return false;
    }
    final total = calcularTotal();
    if (montoRecibidoCentavos != null && montoRecibidoCentavos < total) {
      _ultimoMensaje = 'El monto recibido no cubre el total.';
      notifyListeners();
      return false;
    }

    _procesando = true;
    notifyListeners();
    var guardada = false;
    var stockCambio = false;
    try {
      await _colaDao.guardarOperacionOffline(
        {
          'sucursal_id': sucursalId,
          'cajero_id': cajeroId,
          'total_centavos': total,
          'metodo_pago': 'efectivo',
          'monto_recibido_centavos': ?montoRecibidoCentavos,
          if (montoRecibidoCentavos != null) 'cambio_centavos': montoRecibidoCentavos - total,
          'items': [
            for (final l in _lineas)
              {
                'inventario_id': l.producto.inventarioId,
                'producto_id': l.producto.productoId,
                'talla_id': l.producto.tallaId,
                'color_id': l.producto.colorId,
                'nombre_producto': l.producto.nombre,
                'cantidad': l.cantidad,
                'precio_unitario_centavos': l.producto.precioCentavos,
              },
          ],
        },
        _uuid.v4(),
        Schema.tipoVentaContado,
        clienteId,
        descontarStockLocal: true,
        turnoUuid: turnoUuid,
      );
      guardada = true;
      _puntosUltimaVenta = clienteId == null ? 0 : OfflineConfig.puntosPara(total);
      _lineas.clear();
      _ultimoMensaje = 'Venta guardada localmente. Pendiente de sincronizar.';
    } on TurnoNoAbierto {
      _ultimoMensaje = 'Tu caja ya no está abierta. Ábrela de nuevo para vender.';
    } on StockLocalInsuficiente catch (e) {
      debugPrint('[VentaOfflineProvider] $e');
      stockCambio = true;
      _ultimoMensaje = 'El stock cambió mientras armabas la venta. Revisa el carrito.';
    } catch (e, st) {
      debugPrint('[VentaOfflineProvider] Error al guardar la venta offline: $e\n$st');
      _ultimoMensaje = 'No se pudo guardar la venta.';
    } finally {
      _procesando = false;
    }

    try {
      await _leer(sucursalId);
      if (stockCambio) _ajustarCarritoAlStock();
    } catch (e, st) {
      debugPrint('[VentaOfflineProvider] Error al refrescar tras la venta: $e\n$st');
    }
    notifyListeners();
    return guardada;
  }

  // ---------------------------------------------------------------------------

  Future<void> _leer(int sucursalId) async {
    final filas = await _catalogoDao.obtenerProductos(sucursalId: sucursalId);
    _productos = filas.map(CatalogoItem.fromMap).toList(growable: false);
  }

  /// Tras recargar el catálogo: actualiza cada línea con el producto fresco y la recorta al stock real.
  void _ajustarCarritoAlStock() {
    final porInventario = {for (final p in _productos) p.inventarioId: p};
    final ajustadas = <LineaVenta>[];
    for (final l in _lineas) {
      final fresco = porInventario[l.producto.inventarioId];
      if (fresco == null || !fresco.hayStock) continue;
      final cantidad = l.cantidad > fresco.cantidadDisponible ? fresco.cantidadDisponible : l.cantidad;
      ajustadas.add(LineaVenta(fresco, cantidad));
    }
    _lineas
      ..clear()
      ..addAll(ajustadas);
  }
}
