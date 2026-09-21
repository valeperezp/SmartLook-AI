import 'package:flutter/foundation.dart';
import '../../../checkout/models/pago.dart';
import '../services/pagos_pendientes_service.dart';

class PagosPendientesProvider with ChangeNotifier {
  final PagosPendientesService _service = PagosPendientesService();

  List<Pago> _pagos = [];
  bool _isLoading = false;
  bool _isProcessing = false;
  String? _errorMessage;
  int? _sucursalId;

  // Getters
  List<Pago> get pagos => _pagos;
  int? get sucursalId => _sucursalId;
  bool get isLoading => _isLoading;
  bool get isProcessing => _isProcessing;
  String? get errorMessage => _errorMessage;

  int get totalPendientes => _pagos.length;
  double get montoTotal => _pagos.fold(0.0, (acc, p) => acc + p.monto);

  /// Carga los pagos pendientes de verificación.
  Future<void> cargarPendientes(int? sucursalId, {bool silencioso = false}) async {
    _sucursalId = sucursalId;
    if (!silencioso) {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();
    }

    try {
      _pagos = await _service.listarPendientes(sucursalId: sucursalId);
      _isLoading = false;
      _errorMessage = null;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      if (!silencioso) {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      }
      notifyListeners();
    }
  }

  /// Aprueba un pago QR pendiente.
  Future<bool> confirmarPago(int pagoId) async {
    _isProcessing = true;
    notifyListeners();

    try {
      await _service.confirmarQR(pagoId: pagoId, aprobar: true);
      _pagos.removeWhere((p) => p.id == pagoId);
      _isProcessing = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isProcessing = false;
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  /// Rechaza un pago QR pendiente con motivo.
  Future<bool> rechazarPago(int pagoId, String motivo) async {
    _isProcessing = true;
    notifyListeners();

    try {
      await _service.confirmarQR(pagoId: pagoId, aprobar: false, motivo: motivo);
      _pagos.removeWhere((p) => p.id == pagoId);
      _isProcessing = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isProcessing = false;
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  void limpiarError() {
    _errorMessage = null;
    notifyListeners();
  }
}
