import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartlook_mobile/core/config/regla_puntos.dart';
import 'package:smartlook_mobile/core/models/sucursal.dart';
import 'package:smartlook_mobile/core/models/venta.dart';
import 'package:smartlook_mobile/core/services/catalogo_service.dart';
import 'package:smartlook_mobile/core/services/fidelizacion_service.dart';
import 'package:smartlook_mobile/features/carrito/models/carrito_item.dart';
import 'package:smartlook_mobile/features/checkout/models/venta_online.dart';
import 'package:smartlook_mobile/features/checkout/providers/checkout_provider.dart';
import 'package:smartlook_mobile/features/checkout/services/ventas_online_service.dart';

class _CatalogoFalso extends CatalogoService {
  @override
  Future<List<Sucursal>> listarSucursales() async => [];
}

/// Guarda lo que se le manda y responde con el total que el servidor calcularía (ya con el descuento).
class _VentasFalso extends VentasOnlineService {
  VentaOnlineCreate? recibida;

  @override
  Future<Venta> crearVentaOnline(VentaOnlineCreate data) async {
    recibida = data;
    final total = 39.98 - data.puntosACanjear * 10.0;
    return Venta.fromJson({'id': 10, 'sucursal_id': data.sucursalId, 'canal': 'online', 'estado': 'pendiente', 'total': total});
  }
}

/// 2 × 19.99 = 39.98: con 1 punto = 10.00 el total solo admite 3 puntos.
const _items = [CarritoItem(productoId: 1, nombreProducto: 'Camiseta', precio: 19.99, cantidad: 2)];
const _total = 39.98;

CheckoutProvider _provider({required Future<Map<String, dynamic>> Function(String) servidor, _VentasFalso? ventas}) {
  return CheckoutProvider(
    catalogoService: _CatalogoFalso(),
    ventasOnlineService: ventas ?? _VentasFalso(),
    fidelizacionService: FidelizacionService(obtener: servidor),
  );
}

Future<Map<String, dynamic>> _conSaldo(String _, {int saldo = 5, int valor = 1000}) async =>
    {'cliente_id': 1, 'saldo': saldo, 'valor_punto_centavos': valor};

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ReglaPuntos.restablecer();
  });
  tearDown(ReglaPuntos.restablecer);

  group('Checkout del cliente: canje de puntos (CU17)', () {
    test('pide el saldo y la regla al backend (no están fijos en la app)', () async {
      final checkout = _provider(servidor: (r) => _conSaldo(r, saldo: 5, valor: 2000));

      await checkout.cargarPuntos();

      expect(checkout.puntos!.saldo, 5);
      expect(ReglaPuntos.valorPuntoCentavos, 2000); // la regla de la empresa llegó del servidor
    });

    test('ofrece todos los puntos que tiene sin pasarse del total', () async {
      final checkout = _provider(servidor: _conSaldo); // tiene 5 puntos pero el total solo admite 3
      await checkout.cargarPuntos();

      expect(checkout.puntosUsables(_total), 3);
    });

    test('con pocos puntos ofrece todos los que tiene', () async {
      final checkout = _provider(servidor: (r) => _conSaldo(r, saldo: 2));
      await checkout.cargarPuntos();

      expect(checkout.puntosUsables(_total), 2);
    });

    test('al marcar la casilla el total a pagar baja (y al desmarcarla vuelve)', () async {
      final checkout = _provider(servidor: _conSaldo);
      await checkout.cargarPuntos();
      expect(checkout.montoAPagar(_total), closeTo(39.98, 0.001));

      checkout.setUsarPuntos(true);

      expect(checkout.puntosACanjear(_total), 3);
      expect(checkout.descuentoPuntos(_total), 30.0);
      expect(checkout.montoAPagar(_total), closeTo(9.98, 0.001));

      checkout.setUsarPuntos(false);
      expect(checkout.montoAPagar(_total), closeTo(39.98, 0.001));
    });

    test('la regla de la empresa manda: con puntos de 2.50 el descuento cambia', () async {
      final checkout = _provider(servidor: (r) => _conSaldo(r, saldo: 4, valor: 250));
      await checkout.cargarPuntos();
      checkout.setUsarPuntos(true);

      expect(checkout.puntosACanjear(_total), 4);
      expect(checkout.descuentoPuntos(_total), 10.0);
    });

    test('al crear la orden con la casilla marcada envía puntos_a_canjear y el saldo baja', () async {
      final ventas = _VentasFalso();
      final checkout = _provider(servidor: _conSaldo, ventas: ventas);
      await checkout.cargarPuntos();
      checkout.setUsarPuntos(true);

      await checkout.crearOrden(sucursalId: 1, items: _items);

      expect(ventas.recibida!.puntosACanjear, 3);
      expect(ventas.recibida!.toJson()['puntos_a_canjear'], 3);
      expect(checkout.montoVenta, closeTo(9.98, 0.001)); // lo que se paga es el total del servidor, con descuento
      expect(checkout.puntos!.saldo, 2); // el servidor ya descontó los 3 puntos
    });

    test('sin marcar la casilla NO envía puntos_a_canjear', () async {
      final ventas = _VentasFalso();
      final checkout = _provider(servidor: _conSaldo, ventas: ventas);
      await checkout.cargarPuntos();

      await checkout.crearOrden(sucursalId: 1, items: _items);

      expect(ventas.recibida!.puntosACanjear, 0);
      expect(ventas.recibida!.toJson().containsKey('puntos_a_canjear'), isFalse);
    });

    test('una vez creada la orden ya no se puede cambiar el canje', () async {
      final checkout = _provider(servidor: _conSaldo);
      await checkout.cargarPuntos();
      await checkout.crearOrden(sucursalId: 1, items: _items);

      checkout.setUsarPuntos(true);

      expect(checkout.usarPuntos, isFalse);
    });

    test('si no se puede leer el saldo (sin red) no se ofrece el canje', () async {
      final checkout = _provider(servidor: (_) async => throw Exception('sin red'));

      await checkout.cargarPuntos();

      expect(checkout.puntos, isNull);
      expect(checkout.puntosUsables(_total), 0);
      expect(checkout.montoAPagar(_total), closeTo(39.98, 0.001));
    });

    test('sin puntos no hay nada que canjear', () async {
      final checkout = _provider(servidor: (r) => _conSaldo(r, saldo: 0));
      await checkout.cargarPuntos();
      checkout.setUsarPuntos(true);

      expect(checkout.puntosACanjear(_total), 0);
    });
  });
}
