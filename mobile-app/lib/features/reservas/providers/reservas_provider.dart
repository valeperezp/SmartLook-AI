import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../../core/models/reserva.dart';
import '../../../core/services/reservas_service.dart';
import '../../offline/data/qr_devolucion_dao.dart';
import '../../offline/services/sync_service.dart';

/// Cómo terminó de adjuntar el QR de un reembolso.
enum ResultadoQr {
  /// Llegó al servidor.
  enviado,

  /// Quedó guardado en el celular (sin conexión o sesión vencida): se enviará al volver la red.
  enCola,

  /// El servidor lo rechazó: hay que adjuntar otro.
  rechazado,

  /// La imagen no sirve (vacía, muy grande o no es PNG/JPG/WEBP): no se guardó nada.
  invalido,
}

class ResultadoAdjuntarQr {
  const ResultadoAdjuntarQr(this.resultado, this.mensaje);

  final ResultadoQr resultado;
  final String mensaje;
}

class ReservasProvider extends ChangeNotifier {
  ReservasProvider({ReservasService? service, QrDevolucionDao? qrDao})
      : _service = service ?? ReservasService(),
        _qrDao = qrDao ?? QrDevolucionDao();

  final ReservasService _service;
  final QrDevolucionDao _qrDao;

  /// Estado local del QR de cada pedido cancelado (lo que hay en la cola de sincronización del celular).
  Map<String, QrLocal> _qrLocal = {};

  QrLocal qrLocalDe(Reserva reserva) => _qrLocal[QrDevolucionDao.clavePedido(reservaId: reserva.id)] ?? QrLocal.ninguno;

  Future<void> _cargarQrLocales() async {
    try {
      _qrLocal = await _qrDao.estados();
    } catch (e) {
      debugPrint('[ReservasProvider] No se pudo leer la cola de QR: $e');
    }
  }

  /// Adjunta el QR bancario [imagen] al pedido cancelado [reserva] para recibir el reembolso. Funciona SIN conexión: el QR se
  /// guarda en la cola de sincronización (SUBIR_QR_DEVOLUCION) y [sincronizar] intenta enviarlo ya mismo; si no hay red queda
  /// pendiente y el sincronizador lo envía solo cuando vuelva.
  Future<ResultadoAdjuntarQr> adjuntarQr(
    Reserva reserva, {
    required List<int> imagen,
    String nombreArchivo = 'qr.jpg',
    Future<ResultadoSync> Function()? sincronizar,
  }) async {
    try {
      await _qrDao.encolar(reservaId: reserva.id, imagen: imagen, nombreArchivo: nombreArchivo);
    } on QrInvalido catch (e) {
      return ResultadoAdjuntarQr(ResultadoQr.invalido, e.mensaje);
    } catch (e) {
      debugPrint('[ReservasProvider] No se pudo guardar el QR: $e');
      return const ResultadoAdjuntarQr(ResultadoQr.invalido, 'No se pudo guardar el QR en el celular.');
    }
    await _cargarQrLocales();
    notifyListeners(); // ya se ve como "guardado en el celular"

    if (sincronizar != null) {
      try {
        await sincronizar();
      } catch (e) {
        debugPrint('[ReservasProvider] La sincronización del QR falló: $e'); // sigue en la cola
      }
      await _cargarQrLocales();
    }

    final local = qrLocalDe(reserva);
    if (local.estado == EstadoQrLocal.rechazado) {
      notifyListeners();
      return ResultadoAdjuntarQr(ResultadoQr.rechazado, local.motivo ?? 'El servidor rechazó el QR.');
    }
    if (local.estado == EstadoQrLocal.ninguno) {
      try {
        _reservas = await _service.misReservas(); // el servidor ya tiene el QR: se refleja en la reserva
      } catch (e) {
        debugPrint('[ReservasProvider] No se pudo refrescar las reservas: $e');
      }
      notifyListeners();
      return const ResultadoAdjuntarQr(ResultadoQr.enviado, 'QR enviado. Te haremos la transferencia del reembolso.');
    }
    notifyListeners();
    return const ResultadoAdjuntarQr(ResultadoQr.enCola, 'QR guardado en tu celular. Se enviará cuando vuelva la conexión.');
  }

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
      await _cargarQrLocales();
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
