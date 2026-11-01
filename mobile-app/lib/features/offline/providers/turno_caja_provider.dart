import 'package:flutter/foundation.dart';

import '../../../core/database/app_database.dart';
import '../data/turno_caja_dao.dart';
import '../models/turno_caja.dart';
import 'venta_offline_provider.dart';

/// Qué pasó al intentar cerrar la caja.
enum ResultadoCierre {
  /// Se cerró; el arqueo está en [TurnoCajaProvider.ultimoCierre].
  cerrado,

  /// Hay ventas del turno sin sincronizar: la UI debe advertir y, si el cajero acepta, reintentar con
  /// `confirmarPendientes: true`.
  requiereConfirmacion,

  /// Monto inválido o error al guardar (ver [TurnoCajaProvider.error]).
  error,
}

/// Estado del turno de caja del cajero: abrir caja, ver el arqueo en curso y cerrar caja (CU18).
class TurnoCajaProvider extends ChangeNotifier {
  TurnoCajaProvider({TurnoCajaDao? dao}) : _dao = dao ?? TurnoCajaDao();

  final TurnoCajaDao _dao;

  int? _cajeroId;
  int? _sucursalId;
  TurnoCaja? _turno;
  List<VentaDelTurno> _ventas = const [];
  int _esperadoCentavos = 0;
  int _pendientesSync = 0;
  int _devolucionesNetoCentavos = 0;
  bool _cargando = false;
  bool _guardando = false;
  String? _error;
  ResultadoArqueo? _ultimoCierre;
  int _pendientesAlCerrar = 0;

  TurnoCaja? get turno => _turno;
  bool get hayTurnoAbierto => _turno != null;
  List<VentaDelTurno> get ventas => _ventas;
  int get totalVentasCentavos => _ventas.fold(0, (s, v) => s + v.totalCentavos);

  /// Monto inicial + ventas del turno (lo que debería haber en la caja).
  int get esperadoCentavos => _esperadoCentavos;

  /// Operaciones del turno (ventas y cambios/devoluciones) que todavía no se sincronizaron.
  int get pendientesSync => _pendientesSync;

  /// Efectivo neto de los cambios/devoluciones del turno (positivo = entró, negativo = se reembolsó).
  int get devolucionesNetoCentavos => _devolucionesNetoCentavos;
  bool get cargando => _cargando;
  bool get guardando => _guardando;
  bool get soportado => AppDatabase.soportado;
  String? get error => _error;

  /// Arqueo del último cierre hecho en esta sesión (para mostrarlo hasta que se abra otro turno).
  ResultadoArqueo? get ultimoCierre => _ultimoCierre;

  /// Cuántas ventas pendientes motivaron el último [ResultadoCierre.requiereConfirmacion].
  int get pendientesAlCerrar => _pendientesAlCerrar;

  /// Valida un monto escrito por el usuario. Devuelve el mensaje de error o `null` si es válido.
  static String? validarMonto(String texto) {
    if (texto.trim().isEmpty) return 'Ingresa un monto';
    if (VentaOfflineProvider.parseMonto(texto) == null) return 'Monto inválido (ej. 150 o 150.50)';
    return null;
  }

  /// Lee de SQLite el turno abierto del cajero y su resumen.
  Future<void> cargar(int cajeroId, int sucursalId) async {
    _cajeroId = cajeroId;
    _sucursalId = sucursalId;
    if (!soportado) {
      _error = 'El turno de caja offline no está disponible en web.';
      notifyListeners();
      return;
    }
    _cargando = true;
    notifyListeners();
    try {
      await _leer();
      _error = null;
    } catch (e, st) {
      debugPrint('[TurnoCajaProvider] Error al cargar el turno: $e\n$st');
      _error = 'No se pudo leer el turno de caja.';
    } finally {
      _cargando = false;
      notifyListeners();
    }
  }

  /// Vuelve a leer el turno actual (p. ej. después de una venta).
  Future<void> refrescar() async {
    final cajero = _cajeroId;
    final sucursal = _sucursalId;
    if (cajero != null && sucursal != null) await cargar(cajero, sucursal);
  }

  /// Abre caja con el monto inicial escrito en [montoTexto]. Devuelve si se abrió.
  Future<bool> abrir({required int cajeroId, required int sucursalId, required String montoTexto}) async {
    final problema = validarMonto(montoTexto);
    if (problema != null) {
      _error = problema;
      notifyListeners();
      return false;
    }
    _cajeroId = cajeroId;
    _sucursalId = sucursalId;
    _guardando = true;
    _error = null;
    notifyListeners();
    var abierto = false;
    try {
      await _dao.abrirTurno(cajeroId, sucursalId, VentaOfflineProvider.parseMonto(montoTexto)!);
      _ultimoCierre = null;
      abierto = true;
    } on TurnoYaAbierto {
      _error = 'Ya tienes una caja abierta.';
    } catch (e, st) {
      debugPrint('[TurnoCajaProvider] Error al abrir caja: $e\n$st');
      _error = 'No se pudo abrir la caja.';
    }
    try {
      await _leer();
    } catch (e, st) {
      debugPrint('[TurnoCajaProvider] Error al refrescar tras abrir caja: $e\n$st');
    }
    _guardando = false;
    notifyListeners();
    return abierto;
  }

  /// Cierra la caja con el efectivo contado ([montoRealTexto]).
  Future<ResultadoCierre> cerrar(String montoRealTexto, {bool confirmarPendientes = false}) async {
    final turno = _turno;
    if (turno == null) {
      _error = 'No hay una caja abierta.';
      notifyListeners();
      return ResultadoCierre.error;
    }
    final problema = validarMonto(montoRealTexto);
    if (problema != null) {
      _error = problema;
      notifyListeners();
      return ResultadoCierre.error;
    }

    _guardando = true;
    _error = null;
    notifyListeners();
    var resultado = ResultadoCierre.error;
    try {
      _ultimoCierre = await _dao.cerrarTurno(
        turno.id,
        VentaOfflineProvider.parseMonto(montoRealTexto)!,
        confirmarPendientes: confirmarPendientes,
      );
      resultado = ResultadoCierre.cerrado;
    } on OperacionesPendientesEnTurno catch (e) {
      _pendientesAlCerrar = e.cantidad;
      resultado = ResultadoCierre.requiereConfirmacion;
    } on TurnoNoAbierto {
      _error = 'Esta caja ya no está abierta.';
    } catch (e, st) {
      debugPrint('[TurnoCajaProvider] Error al cerrar caja: $e\n$st');
      _error = 'No se pudo cerrar la caja.';
    }
    try {
      await _leer();
    } catch (e, st) {
      debugPrint('[TurnoCajaProvider] Error al refrescar tras cerrar caja: $e\n$st');
    }
    _guardando = false;
    notifyListeners();
    return resultado;
  }

  /// Oculta el arqueo del último cierre.
  void descartarCierre() {
    _ultimoCierre = null;
    notifyListeners();
  }

  Future<void> _leer() async {
    final cajero = _cajeroId;
    final sucursal = _sucursalId;
    if (cajero == null || sucursal == null) return;
    final fila = await _dao.obtenerTurnoAbierto(cajero, sucursal);
    if (fila == null) {
      _turno = null;
      _ventas = const [];
      _esperadoCentavos = 0;
      _pendientesSync = 0;
      _devolucionesNetoCentavos = 0;
      return;
    }
    final turno = TurnoCaja.fromMap(fila);
    final ventas = await _dao.listarVentasDelTurno(turno.id);
    _turno = turno;
    _ventas = ventas.map(VentaDelTurno.fromMap).toList(growable: false);
    _esperadoCentavos = await _dao.calcularMontoEsperado(turno.id);
    _pendientesSync = await _dao.contarVentasPendientes(turno.id);
    _devolucionesNetoCentavos = await _dao.calcularMovimientoDevoluciones(turno.id);
  }
}
