import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartlook_mobile/features/checkout/models/pago.dart';
import 'package:smartlook_mobile/features/checkout/providers/checkout_provider.dart';
import 'package:smartlook_mobile/features/checkout/widgets/qr_payment_widget.dart';
import 'package:smartlook_mobile/features/encargado/mi_qr/models/sucursal_qr.dart';
import 'package:smartlook_mobile/features/encargado/mi_qr/services/sucursal_qr_service.dart';

/// Servicio de QR de sucursal falso: devuelve lo que se le configure.
class _QrFalso extends SucursalQrService {
  _QrFalso(this.respuesta);

  final Future<SucursalQR?> Function(int sucursalId) respuesta;
  final List<int> consultas = [];

  @override
  Future<SucursalQR?> obtenerQR(int sucursalId) {
    consultas.add(sucursalId);
    return respuesta(sucursalId);
  }
}

SucursalQR _qr(String url, {bool activo = true}) => SucursalQR(
      id: 1,
      sucursalId: 3,
      imagenPath: 'qr/x.png',
      imagenUrl: url,
      activo: activo,
      creadoEn: DateTime(2026, 10, 1),
    );

Pago _pagoPendiente() => Pago(
      id: 77,
      ventaId: 10,
      metodo: 'qr',
      monto: 25.5,
      estado: 'pendiente',
      procesadoEn: DateTime(2026, 10, 1),
      nombreVenta: 'Venta #10',
      montoFormateado: '\$25.50',
    );

void main() {
  late CheckoutProvider checkout;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    checkout = CheckoutProvider();
    // El widget reutiliza el Pago QR pendiente de la venta (F15): así no hace falta red para crearlo
    checkout.marcarPagoExitosoReal(ordenId: 10, pago: _pagoPendiente());
  });

  Future<void> montar(WidgetTester tester, _QrFalso qr) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<CheckoutProvider>.value(
        value: checkout,
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: QrPaymentWidget(ventaId: 10, monto: 25.5, sucursalId: 3, onPagoEnviado: () {}, qrService: qr),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Finder imagenBancaria(String url) => find.byWidgetPredicate((w) => w is Image && w.image is NetworkImage && (w.image as NetworkImage).url == url);

  testWidgets('pide el QR de la sucursal de la orden y muestra su imagen como QR principal', (tester) async {
    final qr = _QrFalso((_) async => _qr('https://api.ejemplo.com/uploads/qr/sucursal_3_abc.png'));
    await montar(tester, qr);

    expect(qr.consultas, [3]);
    expect(imagenBancaria('https://api.ejemplo.com/uploads/qr/sucursal_3_abc.png'), findsOneWidget);
    expect(find.text('La sucursal todavía no cargó su QR'), findsNothing);
    // el QR dinámico NO es el principal: no se dibuja hasta que se pide
    expect(find.byType(QrImageView), findsNothing);
  });

  testWidgets('una ruta relativa del backend se completa con la URL de la API', (tester) async {
    await montar(tester, _QrFalso((_) async => _qr('/uploads/qr/sucursal_3_abc.png')));

    final imagen = tester.widget<Image>(find.byKey(const ValueKey('qr-bancario')));
    final url = (imagen.image as NetworkImage).url;
    expect(url, endsWith('/uploads/qr/sucursal_3_abc.png'));
    expect(url, startsWith('http'));
  });

  testWidgets('sin QR configurado (404) muestra el mensaje y no una imagen', (tester) async {
    await montar(tester, _QrFalso((_) async => null)); // el servicio devuelve null ante un 404

    expect(find.text('La sucursal todavía no cargó su QR'), findsOneWidget);
    expect(find.byKey(const ValueKey('qr-bancario')), findsNothing);
    expect(find.text('Reintentar'), findsNothing); // no es un error: simplemente no hay QR
  });

  testWidgets('un QR desactivado se trata como sin QR', (tester) async {
    await montar(tester, _QrFalso((_) async => _qr('https://x/y.png', activo: false)));
    expect(find.text('La sucursal todavía no cargó su QR'), findsOneWidget);
  });

  testWidgets('si falla la red/servidor avisa distinto y permite reintentar', (tester) async {
    var llamadas = 0;
    final qr = _QrFalso((_) async {
      llamadas++;
      if (llamadas == 1) throw DioException(requestOptions: RequestOptions(path: '/sucursales/3/qr'), type: DioExceptionType.connectionError);
      return _qr('https://api.ejemplo.com/uploads/qr/ok.png');
    });
    await montar(tester, qr);

    expect(find.textContaining('No se pudo cargar el QR de la sucursal'), findsOneWidget);
    expect(find.text('La sucursal todavía no cargó su QR'), findsNothing);

    await tester.tap(find.text('Reintentar'));
    await tester.pump();
    await tester.pump();

    expect(llamadas, 2);
    expect(imagenBancaria('https://api.ejemplo.com/uploads/qr/ok.png'), findsOneWidget);
  });

  testWidgets('el QR dinámico queda como opción secundaria: "Subir comprobante desde el celular"', (tester) async {
    await montar(tester, _QrFalso((_) async => _qr('https://api.ejemplo.com/uploads/qr/a.png')));

    final boton = find.text('Subir comprobante desde el celular');
    expect(boton, findsOneWidget);

    await tester.tap(boton);
    await tester.pump();

    expect(find.byType(QrImageView), findsOneWidget); // abre la página web de comprobantes (/pago/{id}/comprobante)
    expect(find.textContaining('No sirve para pagar'), findsOneWidget);
    // el QR bancario sigue estando arriba
    expect(imagenBancaria('https://api.ejemplo.com/uploads/qr/a.png'), findsOneWidget);

    await tester.tap(boton);
    await tester.pump();
    expect(find.byType(QrImageView), findsNothing);
  });

  testWidgets('el Pago QR pendiente de la venta se reutiliza: no se crea otro', (tester) async {
    await montar(tester, _QrFalso((_) async => _qr('https://x/y.png')));
    expect(find.text('Pago ID: #77'), findsOneWidget);
  });
}
