import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/models/sucursal.dart';
import '../../../core/models/venta.dart';
import '../../../core/services/catalogo_service.dart';
import '../../carrito/models/carrito_item.dart';
import '../models/pago.dart';
import '../models/venta_online.dart';
import '../services/pagos_service.dart';
import '../services/ventas_online_service.dart';

enum EstadoCheckout { idle, creando, esperandoPago, exitoso, error }

class CheckoutProvider extends ChangeNotifier {
  final CatalogoService _catalogoService = CatalogoService();
  final VentasOnlineService _ventasOnlineService = VentasOnlineService();
  final PagosService _pagosService = PagosService();

  EstadoCheckout _estado = EstadoCheckout.idle;
  List<Sucursal> _sucursales = [];
  bool _cargandoSucursales = false;
  int? _sucursalId;
  String _metodoPago = 'tarjeta'; // 'tarjeta' | 'qr'

  int? _ventaId;
  double _montoVenta = 0.0;
  int? _pagoId;
  Pago? _pagoActual;
  int? _ordenFinalizadaId;
  bool _pagoQREnviado = false;
  String? _errorMessage;

  // Getters
  EstadoCheckout get estado => _estado;
  List<Sucursal> get sucursales => _sucursales;
  bool get cargandoSucursales => _cargandoSucursales;
  int? get sucursalId => _sucursalId;
  String get metodoPago => _metodoPago;
  int? get ventaId => _ventaId;
  double get montoVenta => _montoVenta;
  int? get pagoId => _pagoId;
  Pago? get pagoActual => _pagoActual;
  int? get ordenFinalizadaId => _ordenFinalizadaId;
  bool get pagoQREnviado => _pagoQREnviado;
  String? get errorMessage => _errorMessage;

  CheckoutProvider() {
    cargarSucursales();
  }

  Future<void> cargarSucursales() async {
    _cargandoSucursales = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final list = await _catalogoService.listarSucursales();
      _sucursales = list.where((s) => s.activa).toList();
      if (_sucursales.isNotEmpty && _sucursalId == null) {
        _sucursalId = _sucursales.first.id;
      }
    } catch (e) {
      _errorMessage = 'No se pudieron cargar las sucursales disponibles.';
    } finally {
      _cargandoSucursales = false;
      notifyListeners();
    }
  }

  void setSucursalId(int? id) {
    _sucursalId = id;
    _ventaId = null;
    _montoVenta = 0.0;
    _pagoId = null;
    _pagoActual = null;
    _errorMessage = null;
    notifyListeners();
  }

  void setMetodoPago(String metodo) {
    _metodoPago = metodo;
    notifyListeners();
  }

  Future<Venta?> crearOrden({
    required int sucursalId,
    required List<CarritoItem> items,
  }) async {
    if (items.isEmpty) {
      _errorMessage = 'El carrito está vacío';
      _estado = EstadoCheckout.error;
      notifyListeners();
      return null;
    }

    _estado = EstadoCheckout.creando;
    _errorMessage = null;
    notifyListeners();

    try {
      final payload = VentaOnlineCreate(
        sucursalId: sucursalId,
        items: items
            .map((it) => VentaItemCreate(
                  productoId: it.productoId,
                  tallaId: it.tallaId,
                  colorId: it.colorId,
                  cantidad: it.cantidad,
                ))
            .toList(),
      );

      final venta = await _ventasOnlineService.crearVentaOnline(payload);
      _ventaId = venta.id;
      _montoVenta = venta.total;
      _estado = EstadoCheckout.esperandoPago;
      notifyListeners();
      return venta;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      _estado = EstadoCheckout.error;
      notifyListeners();
      return null;
    }
  }

  Future<PaymentIntentResponse?> crearPaymentIntentTarjeta() async {
    if (_ventaId == null) {
      _errorMessage = 'No hay una venta activa para procesar el pago.';
      notifyListeners();
      return null;
    }

    try {
      final intentRes = await _pagosService.crearPaymentIntent(
        ventaId: _ventaId!,
        metodo: 'tarjeta',
      );
      return intentRes;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return null;
    }
  }

  void marcarPagoExitosoReal({required int ordenId, Pago? pago}) {
    _pagoActual = pago;
    _pagoId = pago?.id;
    _ordenFinalizadaId = ordenId;
    _pagoQREnviado = false;
    _estado = EstadoCheckout.exitoso;
    _errorMessage = null;
    notifyListeners();
  }

  Future<bool> procesarPagoTarjeta() async {
    if (_ventaId == null) {
      _errorMessage = 'No hay una venta activa para procesar el pago.';
      _estado = EstadoCheckout.error;
      notifyListeners();
      return false;
    }

    _estado = EstadoCheckout.creando;
    _errorMessage = null;
    notifyListeners();

    try {
      final intentRes = await _pagosService.crearPaymentIntent(
        ventaId: _ventaId!,
        metodo: 'tarjeta',
      );

      try {
        final pago = await _pagosService.confirmarPago(
          paymentIntentId: intentRes.paymentIntentId,
        );
        _pagoId = pago.id;
        _pagoActual = pago;
      } catch (confErr) {
        debugPrint('Confirmación directa de PaymentIntent: $confErr');
      }

      _ordenFinalizadaId = _ventaId;
      _estado = EstadoCheckout.exitoso;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      _estado = EstadoCheckout.error;
      notifyListeners();
      return false;
    }
  }

  Future<Pago?> iniciarPagoQR() async {
    if (_ventaId == null) {
      _errorMessage = 'No hay una venta activa para generar el QR.';
      notifyListeners();
      return null;
    }

    try {
      final pago = await _pagosService.crearPagoQR(ventaId: _ventaId!);
      _pagoId = pago.id;
      _pagoActual = pago;
      notifyListeners();
      return pago;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return null;
    }
  }

  Future<bool> subirQRComprobante(XFile archivo) async {
    if (_pagoId == null && _pagoActual != null) {
      _pagoId = _pagoActual!.id;
    }

    if (_pagoId == null) {
      _errorMessage = 'No se encontró la solicitud de pago QR asociada.';
      notifyListeners();
      return false;
    }

    _estado = EstadoCheckout.creando;
    _errorMessage = null;
    notifyListeners();

    try {
      final pago = await _pagosService.subirComprobante(
        pagoId: _pagoId!,
        archivo: archivo,
      );
      _pagoActual = pago;
      _ordenFinalizadaId = _ventaId;
      _pagoQREnviado = true;
      _estado = EstadoCheckout.exitoso;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      _estado = EstadoCheckout.error;
      notifyListeners();
      return false;
    }
  }

  void reset() {
    _estado = EstadoCheckout.idle;
    _ventaId = null;
    _montoVenta = 0.0;
    _pagoId = null;
    _pagoActual = null;
    _ordenFinalizadaId = null;
    _pagoQREnviado = false;
    _errorMessage = null;
    notifyListeners();
  }
}
