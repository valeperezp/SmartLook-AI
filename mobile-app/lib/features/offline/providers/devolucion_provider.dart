import 'package:flutter/foundation.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/schema.dart';
import '../data/catalogo_local_dao.dart';
import '../data/devolucion_dao.dart';
import '../data/sync_queue_dao.dart' show StockLocalInsuficiente;
import '../data/turno_caja_dao.dart' show TurnoNoAbierto;
import '../models/catalogo_item.dart';
import '../models/devolucion_models.dart';

/// Cambios y devoluciones del cajero (CU11): buscar la venta, elegir qué vuelve y qué se lleva el cliente,
/// ver la diferencia en efectivo y registrarlo todo en SQLite.
class DevolucionProvider extends ChangeNotifier {
  DevolucionProvider({DevolucionDao? dao, CatalogoLocalDao? catalogoDao})
      : _dao = dao ?? DevolucionDao(),
        _catalogoDao = catalogoDao ?? CatalogoLocalDao();

  final DevolucionDao _dao;
  final CatalogoLocalDao _catalogoDao;

  List<VentaLocal> _ventas = const [];
  VentaLocal? _venta;
  final Map<String, int> _devolver = {};
  final List<LineaNueva> _nuevos = [];
  List<CatalogoItem> _catalogo = const [];
  bool _cargando = false;
  bool _guardando = false;
  String? _mensaje;
  String? _avisoPlazo;
  ResultadoDevolucion? _ultimoResultado;

  List<VentaLocal> get ventas => _ventas;
  VentaLocal? get venta => _venta;
  List<LineaNueva> get nuevos => List.unmodifiable(_nuevos);
  List<CatalogoItem> get catalogo => _catalogo;
  bool get cargando => _cargando;
  bool get guardando => _guardando;
  bool get soportado => AppDatabase.soportado;
  int get plazoDias => _dao.plazoDias;

  /// Resultado legible de la última acción, para mostrar en un SnackBar.
  String? get mensaje => _mensaje;
  ResultadoDevolucion? get ultimoResultado => _ultimoResultado;

  /// Aviso (no bloqueo) cuando, según el plazo que informó el backend, la venta abierta parece fuera de plazo. Es solo una
  /// estimación del dispositivo: el servidor decide al sincronizar y puede rechazar el cambio.
  String? get avisoPlazo => _avisoPlazo;

  // ---------------------------------------------------------------------------
  // Búsqueda y selección de la venta
  // ---------------------------------------------------------------------------

  /// Lista las ventas de la sucursal; con [texto] filtra por UUID o número de recibo.
  Future<void> buscar(int sucursalId, {String? texto}) async {
    if (!soportado) {
      _mensaje = 'Los cambios y devoluciones offline no están disponibles en web.';
      notifyListeners();
      return;
    }
    _cargando = true;
    notifyListeners();
    try {
      final filas = await _dao.buscarVentas(sucursalId, texto: texto);
      _ventas = filas.map(VentaLocal.fromMap).toList(growable: false);
      if (texto != null && texto.trim().isNotEmpty && _ventas.isEmpty) _mensaje = 'No se encontró ninguna venta con ese código.';
    } catch (e, st) {
      debugPrint('[DevolucionProvider] Error al buscar ventas: $e\n$st');
      _mensaje = 'No se pudieron leer las ventas.';
    } finally {
      _cargando = false;
      notifyListeners();
    }
  }

  Future<void> cargarCatalogo(int sucursalId) async {
    try {
      final filas = await _catalogoDao.obtenerProductos(sucursalId: sucursalId);
      _catalogo = filas.map(CatalogoItem.fromMap).toList(growable: false);
      notifyListeners();
    } catch (e, st) {
      debugPrint('[DevolucionProvider] Error al leer el catálogo: $e\n$st');
      _mensaje = 'No se pudo leer el catálogo local.';
      notifyListeners();
    }
  }

  /// Abre una venta para devolver/cambiar. Devuelve `false` (con mensaje) si no admite devoluciones.
  Future<bool> seleccionarVenta(String ventaUuid) async {
    try {
      final datos = await _dao.obtenerVentaConItems(ventaUuid);
      if (datos == null) {
        _mensaje = 'La venta no existe en este dispositivo.';
        notifyListeners();
        return false;
      }
      final venta = VentaLocal.fromMap(datos);
      if (venta.items.every((i) => i.devolvible <= 0)) {
        _mensaje = 'Todas las prendas de esta venta ya fueron devueltas.';
        notifyListeners();
        return false;
      }
      _venta = venta;
      _devolver.clear();
      _nuevos.clear();
      _mensaje = null;
      // El plazo de días lo manda el backend; aquí solo se avisa con la estimación guardada (no se bloquea)
      _avisoPlazo = venta.dentroDePlazo(plazoDias)
          ? null
          : 'Pasaron más de $plazoDias días desde la venta (estimación de este dispositivo). El servidor decide: si el plazo venció, '
              'rechazará el cambio al sincronizar y se deshará lo registrado aquí.';
      notifyListeners();
      return true;
    } catch (e, st) {
      debugPrint('[DevolucionProvider] Error al abrir la venta $ventaUuid: $e\n$st');
      _mensaje = 'No se pudo abrir la venta.';
      notifyListeners();
      return false;
    }
  }

  /// Vuelve a la lista de ventas descartando lo armado.
  void limpiar() {
    _venta = null;
    _avisoPlazo = null;
    _devolver.clear();
    _nuevos.clear();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Armado del cambio
  // ---------------------------------------------------------------------------

  int cantidadADevolver(ItemVentaLocal item) => _devolver[item.clave] ?? 0;

  void cambiarDevolucion(ItemVentaLocal item, int delta) {
    final nueva = (cantidadADevolver(item) + delta).clamp(0, item.devolvible);
    if (nueva == 0) {
      _devolver.remove(item.clave);
    } else {
      _devolver[item.clave] = nueva;
    }
    notifyListeners();
  }

  int cantidadNueva(CatalogoItem p) {
    for (final l in _nuevos) {
      if (l.producto.inventarioId == p.inventarioId) return l.cantidad;
    }
    return 0;
  }

  /// Unidades de [p] que todavía se pueden agregar como prenda nueva.
  int disponibleParaAgregar(CatalogoItem p) => p.cantidadDisponible - cantidadNueva(p);

  bool agregarNuevo(CatalogoItem p) {
    if (disponibleParaAgregar(p) <= 0) {
      _mensaje = 'No hay más stock de "${p.nombre}".';
      notifyListeners();
      return false;
    }
    final i = _nuevos.indexWhere((l) => l.producto.inventarioId == p.inventarioId);
    if (i >= 0) {
      _nuevos[i].cantidad++;
    } else {
      _nuevos.add(LineaNueva(p, 1));
    }
    notifyListeners();
    return true;
  }

  void quitarNuevo(CatalogoItem p) {
    final i = _nuevos.indexWhere((l) => l.producto.inventarioId == p.inventarioId);
    if (i < 0) return;
    if (_nuevos[i].cantidad <= 1) {
      _nuevos.removeAt(i);
    } else {
      _nuevos[i].cantidad--;
    }
    notifyListeners();
  }

  /// Valor de lo que vuelve, a los precios de la venta original.
  int get totalDevueltoCentavos {
    final venta = _venta;
    if (venta == null) return 0;
    return venta.items.fold(0, (s, i) => s + i.precioCentavos * cantidadADevolver(i));
  }

  /// Valor de lo que se lleva, a los precios actuales del catálogo.
  int get totalNuevoCentavos => _nuevos.fold(0, (s, l) => s + l.subtotalCentavos);

  /// `nuevo - devuelto`: positivo → el cliente paga; negativo → se le devuelve dinero.
  int get diferenciaCentavos => totalNuevoCentavos - totalDevueltoCentavos;

  String get tipo => _nuevos.isEmpty ? Schema.devolucionSoloDevolucion : Schema.devolucionCambio;

  bool get hayAlgoQueDevolver => totalDevueltoCentavos > 0;
  bool get puedeConfirmar => _venta != null && hayAlgoQueDevolver && !_guardando;

  // ---------------------------------------------------------------------------
  // Confirmación
  // ---------------------------------------------------------------------------

  /// Registra el cambio o la devolución en el turno [turnoUuid]. Devuelve el resultado, o `null` si falló
  /// (el motivo queda en [mensaje]).
  Future<ResultadoDevolucion?> confirmar({required String turnoUuid, String? motivo}) async {
    final venta = _venta;
    if (venta == null || !puedeConfirmar) return null;

    _guardando = true;
    _mensaje = null;
    notifyListeners();
    ResultadoDevolucion? resultado;
    try {
      resultado = await _dao.registrarDevolucion(
        venta.uuid,
        tipo,
        [
          for (final i in venta.items)
            if (cantidadADevolver(i) > 0)
              {'producto_id': i.productoId, 'talla_id': i.tallaId, 'color_id': i.colorId, 'cantidad': cantidadADevolver(i)},
        ],
        [
          for (final l in _nuevos)
            {'producto_id': l.producto.productoId, 'talla_id': l.producto.tallaId, 'color_id': l.producto.colorId, 'cantidad': l.cantidad},
        ],
        turnoUuid,
        motivo: motivo,
      );
      _ultimoResultado = resultado;
      _venta = null;
      _devolver.clear();
      _nuevos.clear();
    } on TurnoNoAbierto {
      _mensaje = 'Tu caja no está abierta. Ábrela para registrar cambios y devoluciones.';
    } on VentaNoDevolvible catch (e) {
      _mensaje = e.motivo;
    } on CantidadDevolucionExcedida catch (e) {
      _mensaje = e.toString();
    } on PrendaNoDisponible catch (e) {
      _mensaje = e.detalle;
    } on StockLocalInsuficiente {
      _mensaje = 'Ya no queda stock de una de las prendas nuevas. Revisa el cambio.';
    } catch (e, st) {
      debugPrint('[DevolucionProvider] Error al registrar la devolución: $e\n$st');
      _mensaje = 'No se pudo registrar el cambio o la devolución.';
    }
    _guardando = false;
    notifyListeners();
    return resultado;
  }
}
