import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlook_mobile/features/cajero/qr/widgets/qr_mostrar_widget.dart';
import 'package:smartlook_mobile/features/encargado/mi_qr/models/sucursal_qr.dart';

SucursalQR _qr({bool activo = true}) => SucursalQR(
      id: 1,
      sucursalId: 1,
      imagenPath: 'qr.png',
      imagenUrl: '/uploads/qr.png',
      activo: activo,
      creadoEn: DateTime(2026, 1, 1),
    );

/// Pantalla de teléfono de [ancho] px lógicos y texto ampliado (accesibilidad): ahí aparecen los desbordes.
Future<void> _pantalla(WidgetTester tester, Widget hijo, {double ancho = 320, double texto = 1.3}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(ancho, 700);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData.dark(useMaterial3: true),
    builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(texto)), child: child!),
    home: Scaffold(body: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: hijo))),
  ));
  await tester.pump();
}

void main() {
  for (final ancho in [320.0, 360.0]) {
    testWidgets('Mi QR (cajero) no desborda en $ancho px con texto grande y QR de sucursal', (tester) async {
      await _pantalla(tester, QrMostrarWidget(urlComprobante: 'https://x/pago/1/comprobante', qrSucursal: _qr()), ancho: ancho);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('sin QR de sucursal solo muestra el QR dinámico', (tester) async {
    await _pantalla(tester, const QrMostrarWidget(urlComprobante: 'https://x/pago/1/comprobante'));
    expect(tester.takeException(), isNull);
    expect(find.byType(SegmentedButton<int>), findsNothing);
  });
}
