import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smartlook_mobile/core/database/app_database.dart';
import 'package:smartlook_mobile/core/models/reserva.dart';
import 'package:smartlook_mobile/core/services/reservas_service.dart';
import 'package:smartlook_mobile/features/offline/data/qr_devolucion_dao.dart';
import 'package:smartlook_mobile/features/offline/data/sync_queue_dao.dart';
import 'package:smartlook_mobile/features/offline/services/sync_service.dart';
import 'package:smartlook_mobile/features/reservas/providers/reservas_provider.dart';
import 'package:smartlook_mobile/features/reservas/screens/mis_reservas_screen.dart';
import 'package:smartlook_mobile/features/reservas/widgets/banner_reembolso.dart';
import 'package:smartlook_mobile/features/reservas/widgets/selector_qr.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// "Mis Reservas": banner rojo en un pedido cancelado → el cliente adjunta su QR bancario (con o sin conexión) para recibir el
/// reembolso. Solo se usa el código real de la app; el servidor y el selector de imagen son falsos.

final _png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, ...List.filled(64, 7)]);

Map<String, dynamic> _json(int id, String estado, {Map<String, dynamic>? reembolso}) => {
      'id': id,
      'cliente_id': 55,
      'sucursal_id': 1,
      'estado': estado,
      'horario_aproximado': null,
      'creada_en': '2026-11-07T10:00:00Z',
      'nombre_sucursal': 'Centro',
      'items': <Map<String, dynamic>>[],
      'total_items': 1,
      'total_unidades': 2,
      'total_estimado': 200.0,
      'reembolso': reembolso,
    };

Reserva _reserva(int id, String estado, {Map<String, dynamic>? reembolso}) => Reserva.fromJson(_json(id, estado, reembolso: reembolso));

Map<String, dynamic> _conQr({String estado = 'pendiente'}) => {
      'id': 9,
      'estado': estado,
      'monto': 200.0,
      'tiene_qr': true,
      'qr_devolucion_url': 'https://api.test/uploads/qr_devolucion/reembolso_9_abc.png',
    };

/// El servicio de reservas FALSO: devuelve lo que se le indique (no sale a la red).
class _ServicioFalso extends ReservasService {
  _ServicioFalso(this.lista);

  List<Reserva> lista;
  int cargas = 0;

  @override
  Future<List<Reserva>> misReservas() async {
    cargas++;
    return lista;
  }
}

/// La cola de QR FALSA en memoria (para las pruebas de pantalla, que no pueden esperar a SQLite): mismas reglas de validación.
class _ColaQrEnMemoria extends QrDevolucionDao {
  final guardados = <({int? reservaId, List<int> imagen, String nombre})>[];
  final rechazados = <String, String>{};

  @override
  Future<String> encolar({int? reservaId, int? ventaId, required List<int> imagen, String nombreArchivo = 'qr.jpg'}) async {
    QrDevolucionDao.validarImagen(imagen);
    guardados.removeWhere((g) => g.reservaId == reservaId);
    guardados.add((reservaId: reservaId, imagen: imagen, nombre: nombreArchivo));
    return 'cola-${guardados.length}';
  }

  @override
  Future<Map<String, QrLocal>> estados() async => {
        for (final g in guardados) QrDevolucionDao.clavePedido(reservaId: g.reservaId): const QrLocal(EstadoQrLocal.enCola),
        for (final MapEntry(:key, :value) in rechazados.entries) 'reserva:$key': QrLocal(EstadoQrLocal.rechazado, motivo: value),
      };
}

void main() {
  // ===================================================================================================================
  group('modelo: la reserva trae su reembolso', () {
    test('Reserva.fromJson lee el reembolso con el QR que subió el cliente; sin reembolso queda null', () {
      final r = _reserva(5, 'cancelada', reembolso: _conQr());

      expect(r.reembolso, isNotNull);
      expect((r.reembolso!.id, r.reembolso!.estado, r.reembolso!.monto), (9, 'pendiente', 200.0));
      expect(r.reembolso!.tieneQr, isTrue);
      expect(r.reembolso!.qrDevolucionUrl, endsWith('reembolso_9_abc.png'));
      expect(_reserva(6, 'cancelada').reembolso, isNull);
    });

    test('admiteReembolso: solo cancelada o reembolso_pendiente (no una reembolsada ni una pendiente/atendida)', () {
      expect({for (final e in ['pendiente', 'confirmada', 'atendida', 'cancelada', 'reembolso_pendiente', 'reembolsada']) e: _reserva(1, e).admiteReembolso}, {
        'pendiente': false,
        'confirmada': false,
        'atendida': false,
        'cancelada': true,
        'reembolso_pendiente': true,
        'reembolsada': false,
      });
      expect(_reserva(1, 'reembolsada').isReembolsada, isTrue);
    });
  });

  // ===================================================================================================================
  group('qué banner corresponde', () {
    const sinNada = QrLocal.ninguno;
    const enCola = QrLocal(EstadoQrLocal.enCola);
    const rechazado = QrLocal(EstadoQrLocal.rechazado, motivo: 'imagen inválida');

    test('un pedido cancelado o con reembolso pendiente y sin QR pide adjuntarlo (banner rojo)', () {
      expect(tipoBannerReembolso(_reserva(1, 'cancelada'), sinNada), TipoBannerReembolso.adjuntar);
      expect(tipoBannerReembolso(_reserva(1, 'reembolso_pendiente'), sinNada), TipoBannerReembolso.adjuntar);
      expect(tipoBannerReembolso(_reserva(1, 'cancelada', reembolso: _conQr()..['tiene_qr'] = false..['qr_devolucion_url'] = null), sinNada), TipoBannerReembolso.adjuntar);
    });

    test('los demás estados no muestran nada, tampoco una reserva ya reembolsada', () {
      for (final estado in ['pendiente', 'confirmada', 'atendida', 'reembolsada']) {
        expect(tipoBannerReembolso(_reserva(1, estado), sinNada), isNull, reason: estado);
        expect(tipoBannerReembolso(_reserva(1, estado), enCola), isNull, reason: estado);
      }
    });

    test('QR guardado en el celular → naranja; el servidor ya lo tiene → verde; rechazado → rojo con otro intento', () {
      expect(tipoBannerReembolso(_reserva(1, 'cancelada'), enCola), TipoBannerReembolso.enCola);
      expect(tipoBannerReembolso(_reserva(1, 'cancelada', reembolso: _conQr()), sinNada), TipoBannerReembolso.recibido);
      expect(tipoBannerReembolso(_reserva(1, 'cancelada'), rechazado), TipoBannerReembolso.rechazado);
      // si cambió el QR y el nuevo todavía está en el celular, manda lo que falta enviar
      expect(tipoBannerReembolso(_reserva(1, 'cancelada', reembolso: _conQr()), enCola), TipoBannerReembolso.enCola);
    });
  });

  // ===================================================================================================================
  group('BannerReembolso (widget)', () {
    Future<void> montar(WidgetTester tester, Reserva r, QrLocal local, {VoidCallback? alTocar}) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: BannerReembolso(reserva: r, local: local, onAdjuntar: alTocar ?? () {})),
      ));
    }

    testWidgets('pedido cancelado: banner ROJO con el texto pedido; al tocarlo se abre la selección del QR', (tester) async {
      var toques = 0;
      await montar(tester, _reserva(5, 'cancelada'), QrLocal.ninguno, alTocar: () => toques++);

      expect(find.text('Tu pedido fue cancelado. Adjunta tu QR para recibir el reembolso'), findsOneWidget);
      final banner = tester.widget<Material>(find.byKey(const Key('banner_reembolso_adjuntar')));
      expect(banner.color, Colors.red.shade700);

      await tester.tap(find.byKey(const Key('banner_reembolso_adjuntar')));
      expect(toques, 1);
    });

    testWidgets('QR rechazado: sigue rojo, muestra el motivo y permite adjuntar otro', (tester) async {
      var toques = 0;
      await montar(tester, _reserva(5, 'cancelada'), const QrLocal(EstadoQrLocal.rechazado, motivo: 'La imagen no es válida'), alTocar: () => toques++);

      expect(find.textContaining('No pudimos usar tu QR'), findsOneWidget);
      expect(find.text('La imagen no es válida'), findsOneWidget);
      await tester.tap(find.byKey(const Key('banner_reembolso_rechazado')));
      expect(toques, 1);
    });

    testWidgets('QR guardado sin conexión (naranja) y QR recibido (verde) informan pero no son tocables', (tester) async {
      var toques = 0;
      await montar(tester, _reserva(5, 'cancelada'), const QrLocal(EstadoQrLocal.enCola), alTocar: () => toques++);
      expect(find.text(BannerReembolso.textoEnCola), findsOneWidget);
      expect(tester.widget<Material>(find.byKey(const Key('banner_reembolso_enCola'))).color, Colors.orange.shade800);
      await tester.tap(find.byKey(const Key('banner_reembolso_enCola')));

      await montar(tester, _reserva(5, 'cancelada', reembolso: _conQr()), QrLocal.ninguno, alTocar: () => toques++);
      expect(find.text(BannerReembolso.textoRecibido), findsOneWidget);
      expect(tester.widget<Material>(find.byKey(const Key('banner_reembolso_recibido'))).color, Colors.green.shade700);
      await tester.tap(find.byKey(const Key('banner_reembolso_recibido')));

      expect(toques, 0);
    });

    testWidgets('si el pedido no está cancelado no se muestra ningún banner', (tester) async {
      for (final estado in ['pendiente', 'atendida', 'reembolsada']) {
        await montar(tester, _reserva(5, estado), QrLocal.ninguno);
        expect(find.byType(Material).evaluate().where((e) => e.widget.key.toString().contains('banner_reembolso')), isEmpty, reason: estado);
        expect(find.textContaining('QR'), findsNothing, reason: estado);
      }
    });
  });

  // ===================================================================================================================
  group('ReservasProvider.adjuntarQr (con SQLite real y un servidor falso)', () {
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

    test('SIN conexión: el QR queda guardado en el celular y el banner pasa a "guardado"', () async {
      final provider = ReservasProvider(service: _ServicioFalso([_reserva(5, 'cancelada')]), qrDao: qr);
      await provider.cargarMisReservas();
      final cancelada = provider.reservas.single;
      expect(tipoBannerReembolso(cancelada, provider.qrLocalDe(cancelada)), TipoBannerReembolso.adjuntar);

      final r = await provider.adjuntarQr(cancelada, imagen: _png, nombreArchivo: 'qr.png', sincronizar: () async => const ResultadoSync(sinRed: true));

      expect(r.resultado, ResultadoQr.enCola);
      expect(r.mensaje, contains('guardado'));
      expect((await colaQr()).single['estado'], 'pendiente');
      expect(tipoBannerReembolso(cancelada, provider.qrLocalDe(cancelada)), TipoBannerReembolso.enCola);
      expect(peticiones, isEmpty);
    });

    test('un fallo del sincronizador (p. ej. se cayó la red a medias) también deja el QR en la cola', () async {
      final provider = ReservasProvider(service: _ServicioFalso([_reserva(5, 'cancelada')]), qrDao: qr);
      await provider.cargarMisReservas();

      final r = await provider.adjuntarQr(provider.reservas.single, imagen: _png, sincronizar: () async => throw Exception('sin red'));

      expect(r.resultado, ResultadoQr.enCola);
      expect((await colaQr()).single['estado'], 'pendiente');
    });

    test('CON conexión: se envía al servidor, queda sincronizado y la reserva se refresca con su QR recibido', () async {
      final servicio = _ServicioFalso([_reserva(5, 'cancelada')]);
      final provider = ReservasProvider(service: servicio, qrDao: qr);
      await provider.cargarMisReservas();
      servicio.lista = [_reserva(5, 'cancelada', reembolso: _conQr())]; // lo que dirá el servidor cuando ya tenga el QR

      final r = await provider.adjuntarQr(
        provider.reservas.single,
        imagen: _png,
        nombreArchivo: 'qr.png',
        sincronizar: sync(dioFalso((o, uuid) => resultado(o, uuid, 'ok'))).sincronizarPendientes,
      );

      expect(r.resultado, ResultadoQr.enviado);
      expect(peticiones.single.path, '/sync/operaciones');
      final enviado = (((peticiones.single.data as Map)['qr_devoluciones']) as List).single as Map;
      expect(enviado['reserva_id'], 5);
      expect(base64Decode(enviado['imagen_base64'] as String), _png);
      expect((await colaQr()).single['estado'], 'sincronizado');
      final actual = provider.reservas.single;
      expect(actual.reembolso?.tieneQr, isTrue);
      expect(tipoBannerReembolso(actual, provider.qrLocalDe(actual)), TipoBannerReembolso.recibido);
    });

    test('si el servidor rechaza el QR el cliente ve el motivo y puede adjuntar otro', () async {
      final provider = ReservasProvider(service: _ServicioFalso([_reserva(5, 'cancelada')]), qrDao: qr);
      await provider.cargarMisReservas();
      final cancelada = provider.reservas.single;

      final r = await provider.adjuntarQr(
        cancelada,
        imagen: _png,
        sincronizar: sync(dioFalso((o, uuid) => resultado(o, uuid, 'conflict', 'El contenido del archivo no es una imagen valida'))).sincronizarPendientes,
      );

      expect(r.resultado, ResultadoQr.rechazado);
      expect(r.mensaje, contains('no es una imagen valida'));
      expect(tipoBannerReembolso(cancelada, provider.qrLocalDe(cancelada)), TipoBannerReembolso.rechazado);

      // adjunta otro y esta vez sí
      final otra = await provider.adjuntarQr(cancelada, imagen: _png, sincronizar: sync(dioFalso((o, uuid) => resultado(o, uuid, 'ok'))).sincronizarPendientes);
      expect(otra.resultado, ResultadoQr.enviado);
      expect(provider.qrLocalDe(cancelada).estado, EstadoQrLocal.ninguno);
    });

    test('una imagen que no sirve se rechaza en el celular: no se guarda ni se envía nada', () async {
      final provider = ReservasProvider(service: _ServicioFalso([_reserva(5, 'cancelada')]), qrDao: qr);
      await provider.cargarMisReservas();

      final r = await provider.adjuntarQr(provider.reservas.single, imagen: utf8.encode('no soy una imagen'), nombreArchivo: 'qr.png');

      expect(r.resultado, ResultadoQr.invalido);
      expect(r.mensaje, contains('imagen'));
      expect(await colaQr(), isEmpty);
    });

    test('al volver a abrir "Mis Reservas" el QR que sigue en la cola se muestra como guardado (sobrevive al reinicio de la app)', () async {
      await qr.encolar(reservaId: 5, imagen: _png);

      final provider = ReservasProvider(service: _ServicioFalso([_reserva(5, 'cancelada')]), qrDao: qr); // proveedor nuevo = app reiniciada
      await provider.cargarMisReservas();

      expect(provider.qrLocalDe(provider.reservas.single).estado, EstadoQrLocal.enCola);
    });
  });

  // ===================================================================================================================
  group('pantalla "Mis Reservas"', () {
    late _ColaQrEnMemoria cola;
    late _ServicioFalso servicio;

    setUp(() {
      cola = _ColaQrEnMemoria();
      servicio = _ServicioFalso([_reserva(1, 'pendiente'), _reserva(5, 'cancelada'), _reserva(6, 'reembolsada'), _reserva(7, 'atendida')]);
    });

    Future<({int elegidos})> montar(WidgetTester tester, {QrElegido? elegido, bool devolverNull = false}) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 3000);
      addTearDown(tester.view.reset);
      var elegidos = 0;
      await tester.pumpWidget(
        ChangeNotifierProvider<ReservasProvider>(
          create: (_) => ReservasProvider(service: servicio, qrDao: cola),
          child: MaterialApp(
            home: MisReservasScreen(
              selectorQr: (_) async {
                elegidos++;
                return devolverNull ? null : (elegido ?? QrElegido(_png, 'mi_qr.png'));
              },
              sincronizar: () async => const ResultadoSync(sinRed: true), // el celular está sin conexión
            ),
          ),
        ),
      );
      await tester.pump(); // initState → cargarMisReservas
      await tester.pump();
      return (elegidos: elegidos);
    }

    testWidgets('solo el pedido CANCELADO muestra el banner rojo; pendiente, atendida y reembolsada no', (tester) async {
      await montar(tester);

      expect(find.text('Reserva #5'), findsOneWidget);
      expect(find.byKey(const Key('banner_reembolso_adjuntar')), findsOneWidget);
      expect(find.text('Tu pedido fue cancelado. Adjunta tu QR para recibir el reembolso'), findsOneWidget);
      expect(find.textContaining('QR'), findsOneWidget);
      expect(find.text('Reembolsada'), findsOneWidget); // la reserva #6 muestra su estado
    });

    testWidgets('SIN conexión: tocar el banner elige el QR, lo guarda en la cola y el banner pasa a "guardado en el celular"', (tester) async {
      await montar(tester);

      await tester.tap(find.byKey(const Key('banner_reembolso_adjuntar')));
      await tester.pump();
      await tester.pump();

      expect(cola.guardados, hasLength(1));
      expect(cola.guardados.single.reservaId, 5);
      expect(cola.guardados.single.imagen, _png);
      expect(cola.guardados.single.nombre, 'mi_qr.png');
      expect(find.byKey(const Key('banner_reembolso_adjuntar')), findsNothing);
      expect(find.byKey(const Key('banner_reembolso_enCola')), findsOneWidget);
      expect(find.text(BannerReembolso.textoEnCola), findsOneWidget);
      expect(find.textContaining('QR guardado en tu celular'), findsOneWidget); // el aviso (SnackBar)
    });

    testWidgets('si el cliente cancela la selección no se guarda nada y el banner sigue igual', (tester) async {
      await montar(tester, devolverNull: true);

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

    testWidgets('un QR que el servidor ya tiene se ve como recibido (verde) y no se vuelve a pedir', (tester) async {
      servicio.lista = [_reserva(5, 'cancelada', reembolso: _conQr())];
      await montar(tester);

      expect(find.byKey(const Key('banner_reembolso_recibido')), findsOneWidget);
      expect(find.text(BannerReembolso.textoRecibido), findsOneWidget);
      expect(find.byKey(const Key('banner_reembolso_adjuntar')), findsNothing);
    });
  });
}
