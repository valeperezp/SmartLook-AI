import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../../core/models/reserva.dart';
import '../../../core/services/reservas_service.dart';

class ReservasProvider extends ChangeNotifier {
  final ReservasService _service = ReservasService();

  List<Reserva> _reservas = [];
  bool _isLoading = false;
  String? _errorMessage;
  Reserva? _ultimaReservaCreada;

  List<Reserva> get reservas => _reservas;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  Reserva? get ultimaReservaCreada => _ultimaReservaCreada;

  Future<bool> crearReserva(ReservaCreate data) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final reserva = await _service.crear(data);
      _ultimaReservaCreada = reserva;
      _reservas.insert(0, reserva);
      _isLoading = false;
      notifyListeners();
      return true;
    } on DioException catch (e) {
      _isLoading = false;
      if (e.response != null && e.response?.data != null) {
        final resData = e.response?.data;
        if (resData is Map && resData.containsKey('detail')) {
          _errorMessage = resData['detail'].toString();
        } else {
          _errorMessage = 'Error al crear la reserva (${e.response?.statusCode})';
        }
      } else {
        _errorMessage = 'Error de conexión con el servidor: ${e.message}';
      }
      notifyListeners();
      return false;
    } catch (e) {
      _isLoading = false;
      _errorMessage = 'Error inesperado: $e';
      notifyListeners();
      return false;
    }
  }

  Future<void> cargarMisReservas() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _reservas = await _service.misReservas();
    } on DioException catch (e) {
      if (e.response != null && e.response?.data != null) {
        final resData = e.response?.data;
        if (resData is Map && resData.containsKey('detail')) {
          _errorMessage = resData['detail'].toString();
        } else {
          _errorMessage = 'Error al obtener reservas (${e.response?.statusCode})';
        }
      } else {
        _errorMessage = 'Error de conexión: ${e.message}';
      }
    } catch (e) {
      _errorMessage = 'Error inesperado: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> cancelarReserva(int id) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final cancelada = await _service.cancelar(id);
      final index = _reservas.indexWhere((r) => r.id == id);
      if (index != -1) {
        _reservas[index] = cancelada;
      }
      _isLoading = false;
      notifyListeners();
      return true;
    } on DioException catch (e) {
      _isLoading = false;
      if (e.response != null && e.response?.data != null) {
        final resData = e.response?.data;
        if (resData is Map && resData.containsKey('detail')) {
          _errorMessage = resData['detail'].toString();
        } else {
          _errorMessage = 'Error al cancelar la reserva (${e.response?.statusCode})';
        }
      } else {
        _errorMessage = 'Error de conexión: ${e.message}';
      }
      notifyListeners();
      return false;
    } catch (e) {
      _isLoading = false;
      _errorMessage = 'Error inesperado: $e';
      notifyListeners();
      return false;
    }
  }

  void limpiarError() {
    _errorMessage = null;
    notifyListeners();
  }
}
