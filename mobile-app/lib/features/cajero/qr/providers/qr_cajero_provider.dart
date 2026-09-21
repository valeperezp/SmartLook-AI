import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../checkout/models/pago.dart';
import '../../../encargado/mi_qr/models/sucursal_qr.dart';
import '../services/qr_cajero_service.dart';

class QrCajeroProvider with ChangeNotifier {
  final QrCajeroService _service = QrCajeroService();

  Pago? _pago;
  SucursalQR? _qrSucursal;

  bool _isLoading = false;
  bool _esperandoComprobante = false;
  bool _comprobanteRecibido = false;
  bool _isProcesando = false;
  bool _pagoCompletado = false;
  String? _errorMessage;

  Timer? _pollingTimer;

  // Getters
  Pago? get pago => _pago;
  SucursalQR? get qrSucursal => _qrSucursal;

  bool get isLoading => _isLoading;
  bool get esperandoComprobante => _esperandoComprobante;
  bool get comprobanteRecibido => _comprobanteRecibido;
  bool get isProcesando => _isProcesando;
  bool get pagoCompletado => _pagoCompletado;
  String? get errorMessage => _errorMessage;

  /// Inicia el flujo de cobro QR para una venta generada en el POS.
  Future<void> iniciarCobroQR({
    required int ventaId,
    required int sucursalId,
  }) async {
    detenerPolling();
    _isLoading = true;
    _pagoCompletado = false;
    _comprobanteRecibido = false;
    _errorMessage = null;
    notifyListeners();

    try {
      final nuevoPago = await _service.generarPagoQR(ventaId);
      _pago = nuevoPago;

      // Cargar QR estático de sucursal si existe
      _qrSucursal = await _service.obtenerQrSucursal(sucursalId);

      _isLoading = false;
      _esperandoComprobante = true;
      notifyListeners();

      // Iniciar polling para detectar subida de comprobante
      _iniciarPolling(nuevoPago.id);
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
    }
  }

  void _iniciarPolling(int pagoId) {
    detenerPolling();
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      try {
        final pagoActualizado = await _service.consultarPago(pagoId);
        _pago = pagoActualizado;

        final tieneComprobante = (pagoActualizado.comprobantePath != null &&
                pagoActualizado.comprobantePath!.isNotEmpty) ||
            (pagoActualizado.comprobanteUrl != null &&
                pagoActualizado.comprobanteUrl!.isNotEmpty);

        if (tieneComprobante) {
          _comprobanteRecibido = true;
          _esperandoComprobante = false;
          detenerPolling();
          notifyListeners();
        }

        if (pagoActualizado.estado.toLowerCase() == 'completado') {
          _pagoCompletado = true;
          detenerPolling();
          notifyListeners();
        }
      } catch (_) {
        // Error de red en polling silencioso
      }
    });
  }

  void detenerPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  /// Aprueba el pago QR luego de revisar el comprobante.
  Future<bool> aprobarPago(int pagoId) async {
    _isProcesando = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final pagoActual = await _service.confirmarCobroQR(pagoId: pagoId, aprobar: true);
      _pago = pagoActual;
      _pagoCompletado = true;
      _isProcesando = false;
      detenerPolling();
      notifyListeners();
      return true;
    } catch (e) {
      _isProcesando = false;
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  /// Rechaza el pago QR por comprobante inválido.
  Future<bool> rechazarPago(int pagoId, String motivo) async {
    _isProcesando = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final pagoActual = await _service.confirmarCobroQR(
        pagoId: pagoId,
        aprobar: false,
        motivo: motivo,
      );
      _pago = pagoActual;
      _isProcesando = false;
      detenerPolling();
      notifyListeners();
      return true;
    } catch (e) {
      _isProcesando = false;
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  void reset() {
    detenerPolling();
    _pago = null;
    _qrSucursal = null;
    _isLoading = false;
    _esperandoComprobante = false;
    _comprobanteRecibido = false;
    _isProcesando = false;
    _pagoCompletado = false;
    _errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    detenerPolling();
    super.dispose();
  }
}
