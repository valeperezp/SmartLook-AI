import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smartlook_mobile/core/database/app_database.dart';
import 'package:smartlook_mobile/core/models/venta.dart';
import 'package:smartlook_mobile/features/mis_compras/providers/ventas_provider.dart';
import 'package:smartlook_mobile/features/mis_compras/screens/mis_compras_screen.dart';
import 'package:smartlook_mobile/features/mis_compras/services/ventas_service.dart';
import 'package:smartlook_mobile/features/offline/data/qr_devolucion_dao.dart';
import 'package:smartlook_mobile/features/offline/data/sync_queue_dao.dart';
import 'package:smartlook_mobile/features/offline/services/sync_service.dart';
import 'package:smartlook_mobile/features/reservas/providers/reservas_provider.dart' show ResultadoQr;
import 'package:smartlook_mobile/features/reservas/widgets/banner_reembolso.dart';
import 'package:smartlook_mobile/features/reservas/widgets/selector_qr.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// "Mis Compras": una compra rechazada por el encargado (su comprobante no sirvió) deja un reembolso pendiente → banner rojo "Tu compra
/// fue rechazada. Adjunta tu QR para recibir el reembolso" → el cliente adjunta su QR (con o sin conexión; SUBIR_QR_DEVOLUCION).
/// Solo se usa el código real de la app; el servidor y el selector de imagen son falsos.

final _png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, ...List.filled(64, 7)]);

Map<String, dynamic> _reembolso({String estado = 'pendiente', bool tieneQr = false}) => {
      'id': 9,
      'estado': estado,
      'venta_id': 41,
      'monto': 200.0,
      'tiene_qr': tieneQr,
      'qr_devolucion_url': tieneQr ? 'https://api.test/uploads/qr_devolucion/reembolso_9_abc.png' : null,
    };

Map<String, dynamic> _json(int id, String estado, {Map<String, dynamic>? reembolso}) => {
      'id': id,
      'cliente_id': 55,
      'sucursal_id': 1,
      'canal': 'online',
      'estado': estado,
      'total': 200.0,
      'creada_en': '2026-11-10T10:00:00Z',
      'nombre_sucursal': 'Centro',
      'items': <Map<String, dynamic>>[],
      'total_items': 1,
      'total_unidades': 2,
      'reembolso': reembolso,
    };

Venta _venta(int id, String estado, {Map<String, dynamic>? reembolso}) => Venta.fromJson(_json(id, estado, reembolso: reembolso));

/// El servicio de compras FALSO: devuelve lo que se le indique (no sale a la red).
class _ServicioFalso extends VentasService {
  _ServicioFalso(this.lista);

  List<Venta> lista;

  @override
  Future<List<Venta>> listarMisCompras() async => lista;
}

/// La cola de QR FALSA en memoria (las pruebas de pantalla no pueden esperar a SQLite): mismas reglas de validación.
class _ColaQrEnMemoria extends QrDevolucionDao {
  final guardados = <({int? ventaId, int? reservaId, List<int> imagen})>[];

  @override
  Future<String> encolar({int? reservaId, int? ventaId, required List<int> imagen, String nombreArchivo = 'qr.jpg'}) async {
    QrDevolucionDao.validarImagen(imagen);
    guardados.removeWhere((g) => g.ventaId == ventaId && g.reservaId == reservaId);
    guardados.add((ventaId: ventaId, reservaId: reservaId, imagen: imagen));
    return 'cola-${guardados.length}';
  }

  @override
  Future<Map<String, QrLocal>> estados() async => {
        for (final g in guardados) QrDevolucionDao.clavePedido(reservaId: g.reservaId, ventaId: g.ventaId): const QrLocal(EstadoQrLocal.enCola),
      };
}

void main() {
  // ===================================================================================================================
  group('modelo: la compra trae su reembolso', () {
    test('Venta.fromJson lee el reembolso con el QR; sin reembolso queda null', () {
      final v = _venta(41, 'cancelada', reembolso: _reembolso(tieneQr: true));

      expect((v.reembolso!.id, v.reembolso!.estado, v.reembolso!.monto, v.reembolso!.tieneQr), (9, 'pendiente', 200.0, true));
      expect(v.reembolso!.qrDevolucionUrl, endsWith('reembolso_9_abc.png'));
      expect(_venta(42, 'completada').reembolso, isNull);
    });

    test('admiteReembolso: solo una compra cancelada/rechazada CON reembolso pendiente (no una que el cliente canceló antes de pagar)', () {
      expect(_venta(1, 'cancelada', reembolso: _reembolso()).admiteReembolso, isTrue);
      expect(_venta(1, 'reembolso_pendiente', reembolso: _reembolso()).admiteReembolso, isTrue);
      expect(_venta(1, 'cancelada').admiteReembolso, isFalse, reason: 'sin reembolso no hay nada que reembolsar');
      expect(_venta(1, 'cancelada', reembolso: _reembolso(estado: 'reembolsado')).admiteReembolso, isFalse);
      expect(_venta(1, 'reembolsada', reembolso: _reembolso(estado: 'reembolsado')).admiteReembolso, isFalse);
      expect(_venta(1, 'completada').admiteReembolso, isFalse);
      expect(_venta(1, 'pendiente').admiteReembolso, isFalse);
      expect(_venta(1, 'reembolsada').isReembolsada, isTrue);
    });
  });

  // ===================================================================================================================
  group('banner de la compra rechazada (widget)', () {
    Future<void> montar(WidgetTester tester, Venta v, QrLocal local, {VoidCallback? alTocar}) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: BannerReembolsoPedido(
            tipo: tipoBannerReembolsoDe(admiteReembolso: v.admiteReembolso, tieneQr: v.reembolso?.tieneQr == true, local: local),
            local: local,
            textoAdjuntar: BannerReembolsoPedido.textoAdjuntarCompra,
            onAdjuntar: alTocar ?? () {},
          ),
        ),
      ));
    }

    testWidgets('compra rechazada con reembolso pendiente: banner ROJO con el texto de la compra; al tocarlo se elige el QR', (tester) async {
      var toques = 0;
      await montar(tester, _venta(41, 'cancelada', reembolso: _reembolso()), QrLocal.ninguno, alTocar: () => toques++);

      expect(find.text('Tu compra fue rechazada. Adjunta tu QR para recibir el reembolso'), findsOneWidget);
      expect(tester.widget<Material>(find.byKey(const Key('banner_reembolso_adjuntar'))).color, Colors.red.shade700);
      await tester.tap(find.byKey(const Key('banner_reembolso_adjuntar')));
      expect(toques, 1);
    });

    testWidgets('guardado sin conexión (naranja) y recibido (verde) informan igual que en las reservas', (tester) async {
      await montar(tester, _venta(41, 'cancelada', reembolso: _reembolso()), const QrLocal(EstadoQrLocal.enCola));
      expect(find.text(BannerReembolsoPedido.textoEnCola), findsOneWidget);
      await montar(tester, _venta(41, 'cancelada', reembolso: _reembolso(tieneQr: true)), QrLocal.ninguno);
      expect(find.text(BannerReembolsoPedido.textoRecibido), findsOneWidget);
    });

    testWidgets('sin reembolso pendiente no se muestra ningún banner', (tester) async {
      for (final v in [_venta(1, 'cancelada'), _venta(2, 'completada'), _venta(3, 'reembolsada', reembolso: _reembolso(estado: 'reembolsado'))]) {
        await montar(tester, v, QrLocal.ninguno);
        expect(find.textContaining('QR'), findsNothing, reason: v.estado);
      }
    });

    testWidgets('el banner de reservas conserva su texto de siempre', (tester) async {
      expect(BannerReembolso.textoAdjuntar, 'Tu pedido fue cancelado. Adjunta tu QR para recibir el reembolso');
    });
  });

  // ===================================================================================================================
  group('VentasProvider.adjuntarQr (con SQLite real y un servidor falso)', () {
    late AppDatabase appDb;
    late SyncQueueDao cola;
    late QrDevolucionDao qr;

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      appDb = AppDatabase.conBaseDeDatos(await AppDatabase.abrir(inMemoryDatabasePath));
      cola = SyncQueueDao(appDatabase: appDb);
      qr = QrDevolucionDao(appDatabase: appDb);
    });

    tearDown(() => appDb.cerrar());

    final peticiones = <RequestOptions>[];
    setUp(peticiones.clear);

    Dio dioFalso(Object Function(RequestOptions o, String uuid) responder) {
      final dio = Dio(BaseOptions(baseUrl: 'http://servidor-falso'));
      dio.interceptors.add(InterceptorsWrapper(onRequest: (o, handler) {
        peticiones.add(o);
        final uuid = (((o.data as Map)['qr_devoluciones'] as List).single as Map)['uuid'] as String;
        final r = responder(o, uuid);
        if (r is DioException) {
          handler.reject(r);
        } else {
          handler.resolve(r as Response<dynamic>);
        }
      }));
      return dio;
    }

    Response<dynamic> resultado(RequestOptions o, String uuid, String status, [String? mensaje]) => Response(requestOptions: o, statusCode: 200, data: {
          'resultados': [
            {'uuid': uuid, 'status': status, if (status == 'ok') 'id_servidor': 9, 'message': ?mensaje},
          ],
        });

    SyncService sync(Dio dio) => SyncService(colaDao: cola, qrDao: qr, hayRed: () async => true, dio: dio);
    Future<List<Map<String, Object?>>> colaQr() async => (await appDb.database)!.query('sync_queue', where: "tipo_operacion = 'SUBIR_QR_DEVOLUCION'");

    Future<(VentasProvider, _ServicioFalso)> proveedor() async {
      final servicio = _ServicioFalso([_venta(41, 'cancelada', reembolso: _reembolso())]);
      final provider = VentasProvider(service: servicio, qrDao: qr);
      await provider.cargarCompras();
      return (provider, servicio);
    }

    test('SIN conexión: el QR queda guardado en el celular como SUBIR_QR_DEVOLUCION de la compra y el banner pasa a "guardado"', () async {
      final (provider, _) = await proveedor();
      final compra = provider.compras.single;
      expect(tipoBannerReembolsoDe(admiteReembolso: compra.admiteReembolso, tieneQr: false, local: provider.qrLocalDe(compra)), TipoBannerReembolso.adjuntar);

      final r = await provider.adjuntarQr(compra, imagen: _png, nombreArchivo: 'qr.png', sincronizar: () async => const ResultadoSync(sinRed: true));

      expect(r.resultado, ResultadoQr.enCola);
      final fila = (await colaQr()).single;
      expect((fila['tipo_operacion'], fila['estado']), ('SUBIR_QR_DEVOLUCION', 'pendiente'));
      final payload = jsonDecode(fila['payload_json'] as String) as Map<String, dynamic>;
      expect(payload['venta_id'], 41);
      expect(payload.containsKey('reserva_id'), isFalse);
      expect(base64Decode(payload['imagen_base64'] as String), _png);
      expect(provider.qrLocalDe(compra).estado, EstadoQrLocal.enCola);
      expect(peticiones, isEmpty);
    });

    test('CON conexión: se envía con `venta_id`, queda sincronizado y la compra se refresca con su QR recibido', () async {
      final (provider, servicio) = await proveedor();
      servicio.lista = [_venta(41, 'cancelada', reembolso: _reembolso(tieneQr: true))]; // lo que dirá el servidor cuando ya tenga el QR

      final r = await provider.adjuntarQr(provider.compras.single, imagen: _png, sincronizar: sync(dioFalso((o, uuid) => resultado(o, uuid, 'ok'))).sincronizarPendientes);

      expect(r.resultado, ResultadoQr.enviado);
      expect(peticiones.single.path, '/sync/operaciones');
      final enviado = (((peticiones.single.data as Map)['qr_devoluciones']) as List).single as Map;
      expect(enviado['venta_id'], 41);
      expect(enviado.containsKey('reserva_id'), isFalse);
      expect(base64Decode(enviado['imagen_base64'] as String), _png);
      expect((await colaQr()).single['estado'], 'sincronizado');
      expect(provider.compras.single.reembolso?.tieneQr, isTrue);
      expect(provider.qrLocalDe(provider.compras.single).estado, EstadoQrLocal.ninguno);
    });

    test('si el servidor lo rechaza el cliente ve el motivo y puede adjuntar otro', () async {
      final (provider, _) = await proveedor();
      final compra = provider.compras.single;

      final r = await provider.adjuntarQr(compra, imagen: _png, sincronizar: sync(dioFalso((o, uuid) => resultado(o, uuid, 'conflict', 'Este pedido ya fue reembolsado'))).sincronizarPendientes);

      expect(r.resultado, ResultadoQr.rechazado);
      expect(r.mensaje, contains('ya fue reembolsado'));
      expect(provider.qrLocalDe(compra).estado, EstadoQrLocal.rechazado);
      final otra = await provider.adjuntarQr(compra, imagen: _png, sincronizar: sync(dioFalso((o, uuid) => resultado(o, uuid, 'ok'))).sincronizarPendientes);
      expect(otra.resultado, ResultadoQr.enviado);
    });

    test('una imagen que no sirve se rechaza en el celular y no se guarda nada', () async {
      final (provider, _) = await proveedor();

      final r = await provider.adjuntarQr(provider.compras.single, imagen: utf8.encode('no soy una imagen'));

      expect(r.resultado, ResultadoQr.invalido);
      expect(await colaQr(), isEmpty);
    });

    test('al reabrir "Mis Compras" el QR que sigue en la cola se muestra como guardado (sobrevive al reinicio)', () async {
      await qr.encolar(ventaId: 41, imagen: _png);

      final provider = VentasProvider(service: _ServicioFalso([_venta(41, 'cancelada', reembolso: _reembolso())]), qrDao: qr);
      await provider.cargarCompras();

      expect(provider.qrLocalDe(provider.compras.single).estado, EstadoQrLocal.enCola);
    });

    test('el QR de una reserva y el de una compra con el mismo número no se confunden', () async {
      await qr.encolar(reservaId: 41, imagen: _png);

      final provider = VentasProvider(service: _ServicioFalso([_venta(41, 'cancelada', reembolso: _reembolso())]), qrDao: qr);
      await provider.cargarCompras();

      expect(provider.qrLocalDe(provider.compras.single).estado, EstadoQrLocal.ninguno);
    });
  });

  // ===================================================================================================================
  group('pantalla "Mis Compras"', () {
    late _ColaQrEnMemoria cola;
    late _ServicioFalso servicio;

    setUp(() {
      cola = _ColaQrEnMemoria();
      servicio = _ServicioFalso([
        _venta(40, 'completada'),
        _venta(41, 'cancelada', reembolso: _reembolso()),
        _venta(42, 'cancelada'), // la canceló el propio cliente antes de pagar: sin reembolso
        _venta(43, 'reembolsada', reembolso: _reembolso(estado: 'reembolsado')),
      ]);
    });

    Future<void> montar(WidgetTester tester, {QrElegido? elegido, bool cancelar = false}) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 4000);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ChangeNotifierProvider<VentasProvider>(
          create: (_) => VentasProvider(service: servicio, qrDao: cola),
          child: MaterialApp(
            home: MisComprasScreen(
              selectorQr: (_) async => cancelar ? null : (elegido ?? QrElegido(_png, 'mi_qr.png')),
              sincronizar: () async => const ResultadoSync(sinRed: true), // el celular está sin conexión
            ),
          ),
        ),
      );
      await tester.pump(); // initState → cargarCompras
      await tester.pump();
    }

    testWidgets('solo la compra rechazada con reembolso pendiente muestra el banner rojo', (tester) async {
      await montar(tester);

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('banner_reembolso_adjuntar')), findsOneWidget);
      expect(find.text('Tu compra fue rechazada. Adjunta tu QR para recibir el reembolso'), findsOneWidget);
      expect(find.textContaining('QR'), findsOneWidget);
    });

    testWidgets('SIN conexión: tocar el banner elige el QR, lo guarda en la cola (con el id de la COMPRA) y pasa a "guardado en el celular"', (tester) async {
      await montar(tester);

      await tester.tap(find.byKey(const Key('banner_reembolso_adjuntar')));
      await tester.pump();
      await tester.pump();

      expect(cola.guardados, hasLength(1));
      expect((cola.guardados.single.ventaId, cola.guardados.single.reservaId), (41, null));
      expect(cola.guardados.single.imagen, _png);
      expect(find.byKey(const Key('banner_reembolso_adjuntar')), findsNothing);
      expect(find.byKey(const Key('banner_reembolso_enCola')), findsOneWidget);
      expect(find.text(BannerReembolsoPedido.textoEnCola), findsOneWidget);
      expect(find.textContaining('QR guardado en tu celular'), findsOneWidget); // el aviso (SnackBar)
    });

    testWidgets('si el cliente cancela la selección no se guarda nada', (tester) async {
      await montar(tester, cancelar: true);

      await tester.tap(find.byKey(const Key('banner_reembolso_adjuntar')));
      await tester.pump();
      await tester.pump();

      expect(cola.guardados, isEmpty);
      expect(find.byKey(const Key('banner_reembolso_adjuntar')), findsOneWidget);
    });

    testWidgets('un archivo que no es imagen se rechaza con un mensaje y el banner sigue pidiendo el QR', (tester) async {
      await montar(tester, elegido: QrElegido(Uint8List.fromList(utf8.encode('esto no es una imagen')), 'qr.png'));

      await tester.tap(find.byKey(const Key('banner_reembolso_adjuntar')));
      await tester.pump();
      await tester.pump();

      expect(cola.guardados, isEmpty);
      expect(find.textContaining('no es una imagen válida'), findsOneWidget);
      expect(find.byKey(const Key('banner_reembolso_adjuntar')), findsOneWidget);
    });

    testWidgets('si el servidor ya tiene el QR se ve como recibido (verde) y no se vuelve a pedir', (tester) async {
      servicio.lista = [_venta(41, 'cancelada', reembolso: _reembolso(tieneQr: true))];
      await montar(tester);

      expect(find.byKey(const Key('banner_reembolso_recibido')), findsOneWidget);
      expect(find.byKey(const Key('banner_reembolso_adjuntar')), findsNothing);
    });
  });
}
