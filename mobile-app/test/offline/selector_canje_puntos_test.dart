import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlook_mobile/core/config/regla_puntos.dart';
import 'package:smartlook_mobile/features/offline/widgets/selector_canje_puntos.dart';

/// CU17 — el cajero pone el N.º de cliente, la app consulta su saldo y ofrece "Usar N puntos (Descuento: $X)".
void main() {
  setUp(ReglaPuntos.restablecer);
  tearDown(ReglaPuntos.restablecer);

  late SeleccionPuntos ultima;

  Future<void> montar(WidgetTester tester, {required int total, required Future<int> Function(int) saldo}) async {
    ultima = (clienteId: null, valido: true, puntos: 0);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SelectorCanjePuntos(totalCentavos: total, consultarSaldo: saldo, alCambiar: (s) => ultima = s),
        ),
      ),
    ));
  }

  /// Escribe el N.º de cliente y espera la consulta (que sale tras una pausa corta al teclear).
  Future<void> escribir(WidgetTester tester, String texto) async {
    await tester.enterText(find.byType(TextField), texto);
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();
  }

  testWidgets('sin cliente no se ofrece nada (la venta sigue normal)', (tester) async {
    await montar(tester, total: 5999, saldo: (_) async => 8);

    expect(find.byKey(const Key('canjear_puntos')), findsNothing);
    expect(ultima, (clienteId: null, valido: true, puntos: 0));
  });

  testWidgets('con un cliente con puntos ofrece "Usar N puntos (Descuento: \$X)" sin pasarse del total', (tester) async {
    await montar(tester, total: 5999, saldo: (_) async => 8); // tiene 8 pero 59.99 solo admite 5 puntos de 10.00

    await escribir(tester, '55');

    expect(find.text('Puntos disponibles: 8 (valen \$80.00)'), findsOneWidget);
    expect(find.text('Usar 5 puntos (Descuento: \$50.00)'), findsOneWidget);
    expect(ultima, (clienteId: 55, valido: true, puntos: 0)); // todavía no marcó la casilla
  });

  testWidgets('al marcar la casilla avisa los puntos que se canjean; al desmarcarla, 0', (tester) async {
    await montar(tester, total: 5999, saldo: (_) async => 8);
    await escribir(tester, '55');

    await tester.tap(find.byKey(const Key('canjear_puntos')));
    await tester.pump();
    expect(ultima, (clienteId: 55, valido: true, puntos: 5));

    await tester.tap(find.byKey(const Key('canjear_puntos')));
    await tester.pump();
    expect(ultima.puntos, 0);
  });

  testWidgets('los puntos que gana el cliente se calculan sobre lo que paga con el descuento', (tester) async {
    await montar(tester, total: 5999, saldo: (_) async => 3);
    await escribir(tester, '55');
    expect(find.text('Cliente ganará 5 punto(s)'), findsOneWidget); // 59.99 → 5 puntos

    await tester.tap(find.byKey(const Key('canjear_puntos')));
    await tester.pump();

    expect(find.text('Cliente ganará 2 punto(s)'), findsOneWidget); // 29.99 → 2 puntos
  });

  testWidgets('la regla de la empresa manda: con puntos de 2.50 se ofrecen más puntos', (tester) async {
    ReglaPuntos.establecer(250);
    await montar(tester, total: 1000, saldo: (_) async => 10);

    await escribir(tester, '55');

    expect(find.text('Usar 4 puntos (Descuento: \$10.00)'), findsOneWidget);
  });

  testWidgets('un cliente sin puntos no ofrece canje', (tester) async {
    await montar(tester, total: 5999, saldo: (_) async => 0);

    await escribir(tester, '55');

    expect(find.byKey(const Key('canjear_puntos')), findsNothing);
    expect(find.text('Puntos disponibles: 0 (valen \$0.00)'), findsOneWidget);
  });

  testWidgets('si el total no alcanza ni para un punto lo dice y no ofrece el canje', (tester) async {
    await montar(tester, total: 500, saldo: (_) async => 5);

    await escribir(tester, '55');

    expect(find.byKey(const Key('canjear_puntos')), findsNothing);
    expect(find.text('El total no alcanza para canjear un punto.'), findsOneWidget);
  });

  testWidgets('si no se puede consultar el saldo (sin red ni datos) la venta sigue sin canje', (tester) async {
    await montar(tester, total: 5999, saldo: (_) async => throw Exception('sin red'));

    await escribir(tester, '55');

    expect(find.text('No se pudo consultar el saldo de puntos.'), findsOneWidget);
    expect(find.byKey(const Key('canjear_puntos')), findsNothing);
    expect(ultima, (clienteId: 55, valido: true, puntos: 0));
  });

  testWidgets('un N.º de cliente inválido se marca y no consulta nada', (tester) async {
    var consultas = 0;
    await montar(tester, total: 5999, saldo: (_) async {
      consultas++;
      return 8;
    });

    await escribir(tester, 'abc');

    expect(find.text('Número de cliente inválido'), findsOneWidget);
    expect(consultas, 0);
    expect(ultima.valido, isFalse);
  });

  testWidgets('al cambiar el N.º de cliente se descarta el canje anterior', (tester) async {
    await montar(tester, total: 5999, saldo: (_) async => 8);
    await escribir(tester, '55');
    await tester.tap(find.byKey(const Key('canjear_puntos')));
    await tester.pump();
    expect(ultima.puntos, 5);

    await tester.enterText(find.byType(TextField), '56'); // otro cliente: el canje del anterior no se arrastra
    await tester.pump();

    expect(ultima, (clienteId: 56, valido: true, puntos: 0));
    expect(find.byKey(const Key('canjear_puntos')), findsNothing);
    await tester.pump(const Duration(milliseconds: 450)); // deja correr la consulta pendiente
  });
}
