import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import '../models/sucursal_qr.dart';
import '../services/sucursal_qr_service.dart';

class SucursalQrProvider with ChangeNotifier {
  final SucursalQrService _service = SucursalQrService();

  SucursalQR? _qr;
  bool _isLoading = false;
  bool _isSubiendo = false;
  String? _errorMessage;

  // Getters
  SucursalQR? get qr => _qr;
  bool get tieneQr => _qr != null && _qr!.activo;
  bool get isLoading => _isLoading;
  bool get isSubiendo => _isSubiendo;
  String? get errorMessage => _errorMessage;

  /// Carga el QR activo de la sucursal.
  Future<void> cargarQR(int sucursalId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _qr = await _service.obtenerQR(sucursalId);
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
    }
  }

  /// Sube y activa un nuevo código QR.
  Future<bool> subirQR(int sucursalId, XFile archivo) async {
    _isSubiendo = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final nuevoQr = await _service.subirQR(sucursalId, archivo);
      _qr = nuevoQr;
      _isSubiendo = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isSubiendo = false;
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  /// Desactiva el código QR actual.
  Future<bool> desactivarQR(int sucursalId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _service.desactivarQR(sucursalId);
      _qr = null;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
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
