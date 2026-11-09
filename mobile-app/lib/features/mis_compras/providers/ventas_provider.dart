import 'package:flutter/foundation.dart';
import '../../../core/models/venta.dart';
import '../../offline/data/qr_devolucion_dao.dart';
import '../../offline/services/sync_service.dart';
import '../../reservas/providers/reservas_provider.dart' show ResultadoAdjuntarQr, ResultadoQr;
import '../services/ventas_service.dart';

class VentasProvider extends ChangeNotifier {
  VentasProvider({VentasService? service, QrDevolucionDao? qrDao})
      : _service = service ?? VentasService(),
        _qrDao = qrDao ?? QrDevolucionDao();

  final VentasService _service;
  final QrDevolucionDao _qrDao;

  /// Estado local del QR de cada compra con reembolso pendiente (lo que hay en la cola de sincronización del celular).
  Map<String, QrLocal> _qrLocal = {};

  QrLocal qrLocalDe(Venta venta) => _qrLocal[QrDevolucionDao.clavePedido(ventaId: venta.id)] ?? QrLocal.ninguno;

  Future<void> _cargarQrLocales() async {
    try {
      _qrLocal = await _qrDao.estados();
    } catch (e) {
      debugPrint('[VentasProvider] No se pudo leer la cola de QR: $e');
    }
  }

  /// Adjunta el QR bancario [imagen] a la compra rechazada [venta] para recibir el reembolso. Funciona SIN conexión: el QR se guarda
  /// en la cola de sincronización (SUBIR_QR_DEVOLUCION) y [sincronizar] intenta enviarlo ya mismo; si no hay red queda pendiente y
  /// el sincronizador lo envía solo cuando vuelva.
  Future<ResultadoAdjuntarQr> adjuntarQr(
    Venta venta, {
    required List<int> imagen,
    String nombreArchivo = 'qr.jpg',
    Future<ResultadoSync> Function()? sincronizar,
  }) async {
    try {
      await _qrDao.encolar(ventaId: venta.id, imagen: imagen, nombreArchivo: nombreArchivo);
    } on QrInvalido catch (e) {
      return ResultadoAdjuntarQr(ResultadoQr.invalido, e.mensaje);
    } catch (e) {
      debugPrint('[VentasProvider] No se pudo guardar el QR: $e');
      return const ResultadoAdjuntarQr(ResultadoQr.invalido, 'No se pudo guardar el QR en el celular.');
    }
    await _cargarQrLocales();
    notifyListeners(); // ya se ve como "guardado en el celular"

    if (sincronizar != null) {
      try {
        await sincronizar();
      } catch (e) {
        debugPrint('[VentasProvider] La sincronización del QR falló: $e'); // sigue en la cola
      }
      await _cargarQrLocales();
    }

    final local = qrLocalDe(venta);
    if (local.estado == EstadoQrLocal.rechazado) {
      notifyListeners();
      return ResultadoAdjuntarQr(ResultadoQr.rechazado, local.motivo ?? 'El servidor rechazó el QR.');
    }
    if (local.estado == EstadoQrLocal.ninguno) {
      try {
        _compras = await _service.listarMisCompras(); // el servidor ya tiene el QR: se refleja en la compra
      } catch (e) {
        debugPrint('[VentasProvider] No se pudo refrescar las compras: $e');
      }
      notifyListeners();
      return const ResultadoAdjuntarQr(ResultadoQr.enviado, 'QR enviado. Te haremos la transferencia del reembolso.');
    }
    notifyListeners();
    return const ResultadoAdjuntarQr(ResultadoQr.enCola, 'QR guardado en tu celular. Se enviará cuando vuelva la conexión.');
  }

  List<Venta> _compras = [];
  bool _isLoading = false;
  String? _errorMessage;
  Venta? _ventaSeleccionada;

  List<Venta> get compras => List.unmodifiable(_compras);
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  Venta? get ventaSeleccionada => _ventaSeleccionada;

  Future<void> cargarCompras() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _compras = await _service.listarMisCompras();
      await _cargarQrLocales();
    } catch (e) {
      _errorMessage = 'Error al cargar compras: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Venta?> cargarDetalle(int id) async {
    try {
      final venta = await _service.obtenerVenta(id);
      _ventaSeleccionada = venta;
      notifyListeners();
      return venta;
    } catch (e) {
      debugPrint('Error al obtener detalle de venta: $e');
      return null;
    }
  }

  void limpiarSeleccion() {
    _ventaSeleccionada = null;
    notifyListeners();
  }
}
