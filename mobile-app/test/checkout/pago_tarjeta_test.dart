import 'package:flutter_test/flutter_test.dart';
import 'package:smartlook_mobile/core/models/sucursal.dart';
import 'package:smartlook_mobile/core/models/venta.dart';
import 'package:smartlook_mobile/core/services/catalogo_service.dart';
import 'package:smartlook_mobile/features/carrito/models/carrito_item.dart';
import 'package:smartlook_mobile/features/checkout/models/pago.dart';
import 'package:smartlook_mobile/features/checkout/models/venta_online.dart';
import 'package:smartlook_mobile/features/checkout/providers/checkout_provider.dart';
import 'package:smartlook_mobile/features/checkout/services/pagos_service.dart';
import 'package:smartlook_mobile/features/checkout/services/ventas_online_service.dart';

class _CatalogoFalso extends CatalogoService {
  @override
  Future<List<Sucursal>> listarSucursales() async => [];
}

class _VentasFalso extends VentasOnlineService {
  @override
  Future<Venta> crearVentaOnline(VentaOnlineCreate data) async =>
      Venta.fromJson({'id': 10, 'sucursal_id': data.sucursalId, 'canal': 'online', 'estado': 'pendiente', 'total': 25.5});
}

/// Pagos falso: `confirmar` decide qué responde el backend a /pagos/confirmar.
class _PagosFalso extends PagosService {
  _PagosFalso(this.confirmar);

  final Future<Pago> Function() confirmar;
  int confirmaciones = 0;

  @override
  Future<PaymentIntentResponse> crearPaymentIntent({required int ventaId, String metodo = 'tarjeta'}) async =>
      const PaymentIntentResponse(clientSecret: 'cs_test', paymentIntentId: 'pi_test', monto: 25.5, moneda: 'usd');

  @override
  Future<Pago> confirmarPago({required String paymentIntentId}) {
    confirmaciones++;
    return confirmar();
  }
}

Pago _pago(String estado) => Pago(
      id: 5,
      ventaId: 10,
      metodo: 'tarjeta',
      monto: 25.5,
      estado: estado,
      procesadoEn: DateTime(2026, 10, 1),
      nombreVenta: 'Venta #10',
      montoFormateado: '\$25.50',
    );

const _item = CarritoItem(productoId: 1, nombreProducto: 'Camiseta', precio: 25.5, cantidad: 1);

void main() {
  Future<CheckoutProvider> conOrden(_PagosFalso pagos) async {
    final checkout = CheckoutProvider(catalogoService: _CatalogoFalso(), ventasOnlineService: _VentasFalso(), pagosService: pagos);
    await checkout.crearOrden(sucursalId: 1, items: [_item]);
    expect(checkout.ventaId, 10);
    return checkout;
  }

  test('si el backend devuelve "completado", la orden queda pagada', () async {
    final pagos = _PagosFalso(() async => _pago('completado'));
    final checkout = await conOrden(pagos);

    expect(await checkout.procesarPagoTarjeta(), isTrue);

    expect(checkout.estado, EstadoCheckout.exitoso);
    expect(checkout.ordenFinalizadaId, 10);
    expect(checkout.pagoActual?.estado, 'completado');
    expect(pagos.confirmaciones, 1);
  });

  test('si el backend devuelve "fallido", NO es exitoso y se puede reintentar con una orden nueva', () async {
    final checkout = await conOrden(_PagosFalso(() async => _pago('fallido')));

    expect(await checkout.procesarPagoTarjeta(), isFalse);

    expect(checkout.estado, EstadoCheckout.error);
    expect(checkout.ordenFinalizadaId, isNull);
    expect(checkout.errorMessage, contains('Error al procesar el pago'));
    // el backend canceló la orden: se limpia para poder crear otra
    expect(checkout.ventaId, isNull);
    expect(checkout.pagoActual, isNull);
  });

  test('si el pago sigue "pendiente" tampoco es exitoso, pero conserva la orden', () async {
    final checkout = await conOrden(_PagosFalso(() async => _pago('pendiente')));

    expect(await checkout.procesarPagoTarjeta(), isFalse);

    expect(checkout.estado, EstadoCheckout.error);
    expect(checkout.ordenFinalizadaId, isNull);
    expect(checkout.errorMessage, allOf(contains('Error al procesar el pago'), contains('pendiente')));
    expect(checkout.ventaId, 10);
  });

  test('si /pagos/confirmar falla (400/500), la orden no se da por pagada', () async {
    final checkout = await conOrden(_PagosFalso(() async => throw Exception('Error 500 del servidor')));

    expect(await checkout.procesarPagoTarjeta(), isFalse);

    expect(checkout.estado, EstadoCheckout.error);
    expect(checkout.ordenFinalizadaId, isNull);
    expect(checkout.errorMessage, allOf(startsWith('Error al procesar el pago'), contains('500')));
  });

  test('sin orden activa no hace nada', () async {
    final checkout = CheckoutProvider(catalogoService: _CatalogoFalso(), ventasOnlineService: _VentasFalso(), pagosService: _PagosFalso(() async => _pago('completado')));
    expect(await checkout.procesarPagoTarjeta(), isFalse);
    expect(checkout.estado, EstadoCheckout.error);
  });
}
