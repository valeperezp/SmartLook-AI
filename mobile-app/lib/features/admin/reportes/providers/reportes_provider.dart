import 'package:flutter/foundation.dart';
import '../models/reporte_models.dart';
import '../services/reportes_service.dart';

class ReportesProvider with ChangeNotifier {
  final ReportesService _service = ReportesService();

  ResumenReportes? _resumen;
  List<ReservasPorDia> _reservasPorDia = [];
  List<ReservasPorSucursal> _reservasPorSucursal = [];
  List<ReservasPorEstado> _reservasPorEstado = [];

  bool _isLoading = false;
  String? _errorMessage;

  int? _sucursalSeleccionadaId;
  int _diasFiltro = 14;

  // Getters
  ResumenReportes? get resumen => _resumen;
  List<ReservasPorDia> get reservasPorDia => _reservasPorDia;
  List<ReservasPorSucursal> get reservasPorSucursal => _reservasPorSucursal;
  List<ReservasPorEstado> get reservasPorEstado => _reservasPorEstado;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  int? get sucursalSeleccionadaId => _sucursalSeleccionadaId;
  int get diasFiltro => _diasFiltro;

  /// Carga todos los datos de reportes en paralelo.
  Future<void> cargarReportes({
    int? sucursalId,
    int? dias,
  }) async {
    if (sucursalId != null) {
      _sucursalSeleccionadaId = sucursalId;
    }
    if (dias != null) {
      _diasFiltro = dias;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final effectiveSucursal = _sucursalSeleccionadaId;
      final results = await Future.wait([
        _service.resumen(sucursalId: effectiveSucursal),
        _service.reservasPorDia(
          sucursalId: effectiveSucursal,
          dias: _diasFiltro,
        ),
        _service.reservasPorSucursal(),
        _service.reservasPorEstado(sucursalId: effectiveSucursal),
      ]);

      _resumen = results[0] as ResumenReportes;
      _reservasPorDia = results[1] as List<ReservasPorDia>;
      _reservasPorSucursal = results[2] as List<ReservasPorSucursal>;
      _reservasPorEstado = results[3] as List<ReservasPorEstado>;
      _isLoading = false;
      _errorMessage = null;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
    }
  }

  /// Cambia el filtro de sucursal (null = todas).
  Future<void> cambiarSucursal(int? sucursalId) async {
    _sucursalSeleccionadaId = sucursalId;
    await cargarReportes();
  }

  /// Cambia el periodo en días (ej: 7, 14, 30).
  Future<void> cambiarDias(int dias) async {
    _diasFiltro = dias;
    await cargarReportes();
  }
}
