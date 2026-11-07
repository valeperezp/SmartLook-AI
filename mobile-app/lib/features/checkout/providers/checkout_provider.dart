import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/config/regla_puntos.dart';
import '../../../core/models/sucursal.dart';
import '../../../core/models/venta.dart';
import '../../../core/services/catalogo_service.dart';
import '../../../core/services/fidelizacion_service.dart';
import '../../carrito/models/carrito_item.dart';
import '../models/pago.dart';
import '../models/venta_online.dart';
import '../services/pagos_service.dart';
import '../services/ventas_online_service.dart';

enum EstadoCheckout { idle, creando, esperandoPago, exitoso, error }

class CheckoutProvider extends ChangeNotifier {
  final CatalogoService _catalogoService;
  final VentasOnlineService _ventasOnlineService;
  final PagosService _pagosService;
  final FidelizacionService _fidelizacionService;

  // Puntos de fidelización (CU17): saldo y regla vienen del backend
  PuntosServidor? _puntos;
  bool _usarPuntos = false;

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

  /// Saldo de puntos del cliente y regla de su empresa (null si no se pudo leer del servidor).
  PuntosServidor? get puntos => _puntos;
  bool get usarPuntos => _usarPuntos;

  /// Puntos que se pueden canjear en una compra de [totalCarrito]: todos los que tiene, sin que el descuento supere el total.
  int puntosUsables(double totalCarrito) =>
      ReglaPuntos.puntosUsables(saldo: _puntos?.saldo ?? 0, totalCentavos: (totalCarrito * 100).round());

  /// Puntos que realmente se canjean (0 si el cliente no marcó la casilla).
  int puntosACanjear(double totalCarrito) => _usarPuntos ? puntosUsables(totalCarrito) : 0;

  /// Descuento (en moneda) por los puntos que se canjean.
  double descuentoPuntos(double totalCarrito) => ReglaPuntos.descuentoCentavos(puntosACanjear(totalCarrito)) / 100;

  /// Lo que paga el cliente: el total del carrito menos el descuento por puntos.
  double totalAPagar(double totalCarrito) {
    final t = totalCarrito - descuentoPuntos(totalCarrito);
    return t < 0 ? 0 : t;
  }

  /// Lo que se muestra como "Total a pagar": el de la orden ya creada (con descuento) o el estimado del carrito.
  double montoAPagar(double totalCarrito) => _ventaId != null ? _montoVenta : totalAPagar(totalCarrito);

  /// Los servicios se pueden inyectar (para pruebas); por defecto usan la API real.
  CheckoutProvider({
    CatalogoService? catalogoService,
    VentasOnlineService? ventasOnlineService,
    PagosService? pagosService,
    FidelizacionService? fidelizacionService,
  })  : _catalogoService = catalogoService ?? CatalogoService(),
        _ventasOnlineService = ventasOnlineService ?? VentasOnlineService(),
        _pagosService = pagosService ?? PagosService(),
        _fidelizacionService = fidelizacionService ?? FidelizacionService() {
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

  /// Pide al backend el saldo de puntos y la regla de la empresa. Sin red o sin sesión de cliente no se ofrece el canje.
  Future<void> cargarPuntos() async {
    try {
      _puntos = await _fidelizacionService.misPuntos();
    } catch (e) {
      debugPrint('[CheckoutProvider] No se pudo leer el saldo de puntos: $e');
      _puntos = null;
    }
    notifyListeners();
  }

  void setUsarPuntos(bool usar) {
    if (_ventaId != null) return; // la orden ya se creó con (o sin) el canje
    _usarPuntos = usar;
    notifyListeners();
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
      final totalCarrito = items.fold<double>(0, (suma, it) => suma + it.subtotal);
      final canje = puntosACanjear(totalCarrito);
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
        puntosACanjear: canje,
      );

      final venta = await _ventasOnlineService.crearVentaOnline(payload);
      _ventaId = venta.id;
      _montoVenta = venta.total;
      if (canje > 0 && _puntos != null) {
        // El servidor ya descontó los puntos del saldo
        _puntos = PuntosServidor(clienteId: _puntos!.clienteId, saldo: _puntos!.saldo - canje, valorPuntoCentavos: _puntos!.valorPuntoCentavos);
      }
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

      // Un fallo de red/servidor aquí cae al catch de abajo: la orden NO se da por pagada.
      final pago = await _pagosService.confirmarPago(
        paymentIntentId: intentRes.paymentIntentId,
      );
      _pagoId = pago.id;
      _pagoActual = pago;

      // Solo el estado 'completado' del backend significa pago exitoso.
      if (pago.estado != 'completado') {
        debugPrint('Pago con tarjeta no completado: estado ${pago.estado}');
        if (pago.estado == 'fallido') {
          // El backend cancela la orden online cuando el cobro falla: para reintentar hay que crear una nueva.
          _ventaId = null;
          _montoVenta = 0.0;
          _pagoId = null;
          _pagoActual = null;
          _errorMessage = 'Error al procesar el pago: el cobro no se completó. Intentá de nuevo.';
        } else {
          _errorMessage = 'Error al procesar el pago: todavía no se confirmó (estado: ${pago.estado}). Intentá de nuevo en unos instantes.';
        }
        _estado = EstadoCheckout.error;
        notifyListeners();
        return false;
      }

      _ordenFinalizadaId = _ventaId;
      _estado = EstadoCheckout.exitoso;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Error al procesar el pago: ${e.toString().replaceAll('Exception: ', '')}';
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

  /// Reinicia solo el estado del pago para permitir crear una venta NUEVA
  /// al reintentar. No toca la sucursal seleccionada ni el método de pago.
  void resetearCheckout() {
    _ventaId = null;
    _pagoId = null;
    _pagoActual = null;
    _estado = EstadoCheckout.idle;
    _errorMessage = null;
    notifyListeners();
    cargarPuntos(); // si la orden se canceló, el servidor devolvió los puntos canjeados
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
