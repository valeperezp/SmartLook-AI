import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smartlook_mobile/core/database/app_database.dart';
import 'package:smartlook_mobile/core/database/schema.dart';
import 'package:smartlook_mobile/features/auth/providers/auth_provider.dart';
import 'package:smartlook_mobile/features/offline/data/suscripcion_stock_dao.dart';
import 'package:smartlook_mobile/features/offline/models/catalogo_item.dart';
import 'package:smartlook_mobile/features/offline/providers/catalogo_offline_provider.dart';
import 'package:smartlook_mobile/features/offline/providers/conectividad_provider.dart';
import 'package:smartlook_mobile/features/offline/providers/suscripciones_provider.dart';
import 'package:smartlook_mobile/features/offline/screens/catalogo_offline_screen.dart';
import 'package:smartlook_mobile/features/offline/services/suscripciones_remotas.dart';
import 'package:smartlook_mobile/features/offline/services/sync_service.dart';
import 'package:sqflite/sqflite.dart' show Sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// El servidor FALSO de los avisos de stock: guarda lo que recibe y responde según cómo se configure.
class _ApiFalsa implements ApiSuscripciones {
  bool sinRed = false;
  int? rechazarCon;
  String estadoAlCrear = 'pendiente';
  List<Map<String, dynamic>> notificaciones = [];
  final recibidas = <Map<String, dynamic>>[];
  int vistas = 0;
  int _id = 500;

  @override
  Future<Map<String, dynamic>> crear(Map<String, dynamic> cuerpo) async {
    if (sinRed) throw Exception('sin red');
    if (rechazarCon != null) throw RechazoServidor(rechazarCon!, 'Producto no encontrado');
    recibidas.add(cuerpo);
    return {...cuerpo, 'id': _id++, 'estado': estadoAlCrear, 'visto': false};
  }

  @override
  Future<List<Map<String, dynamic>>> misNotificaciones() async {
    if (sinRed) throw Exception('sin red');
    return notificaciones;
  }

  @override
  Future<void> marcarVistas() async {
    if (sinRed) throw Exception('sin red');
    vistas++;
  }
}

CatalogoItem _agotado({int producto = 107}) => CatalogoItem(
      inventarioId: 1,
      sucursalId: 1,
      productoId: producto,
      tallaId: 1,
      colorId: 5,
      nombre: 'Falda plisada',
      nombreTalla: 'S',
      nombreColor: 'Negro',
      precioCentavos: 3999,
      cantidadDisponible: 0,
      activo: true,
    );

/// CU16 — los avisos "Avísame cuando llegue" se sincronizan con el servidor; sin red quedan en la cola local.
void main() {
  const cliente = 55;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('con la base local', () {
    late AppDatabase appDb;
    late SuscripcionStockDao dao;
    late _ApiFalsa api;
    late SuscripcionesProvider provider;

    setUp(() async {
      appDb = AppDatabase.conBaseDeDatos(await AppDatabase.abrir(inMemoryDatabasePath));
      dao = SuscripcionStockDao(appDatabase: appDb);
      api = _ApiFalsa();
      provider = SuscripcionesProvider(dao: dao, remoto: SuscripcionesRemotas(api: api, dao: dao), esperaServidor: const Duration(seconds: 2));
    });

    tearDown(() => appDb.cerrar());

    Future<Map<String, Object?>> fila() async => (await (await appDb.database)!.query(Schema.tablaSuscripcionesStock)).single;

    test('con red, "Avísame" llega al servidor de una vez (con el id local como uuid) y queda sincronizado', () async {
      expect(await provider.suscribirse(_agotado(), cliente), isTrue);

      final enviada = api.recibidas.single;
      expect((enviada['producto_id'], enviada['talla_id'], enviada['color_id'], enviada['sucursal_id']), (107, 1, 5, 1));
      final local = await fila();
      expect(enviada['uuid'], local['id']);
      expect((local['sync_estado'], local['id_servidor']), ('sincronizado', 500));
      expect(provider.mensaje, 'Te avisaremos cuando llegue "Falda plisada".');
    });

    test('SIN internet queda guardado en la cola local (pendiente) y avisa que se enviará al volver la conexión', () async {
      api.sinRed = true;

      expect(await provider.suscribirse(_agotado(), cliente), isTrue);

      expect(provider.mensaje, contains('Sin conexión'));
      expect(provider.mensaje, contains('se enviará al volver la conexión'));
      expect((await fila())['sync_estado'], 'pendiente');
      expect(await dao.obtenerPorEnviar(cliente), hasLength(1));
      expect(provider.pendientes, hasLength(1)); // para el cliente ya figura como esperada
    });

    test('al volver la red se envía lo guardado, con el mismo uuid (reenviar no duplica)', () async {
      api.sinRed = true;
      await provider.suscribirse(_agotado(), cliente);
      final uuid = (await fila())['id'];
      api.sinRed = false;

      final hayNuevos = await provider.sincronizarConServidor(cliente);

      expect(hayNuevos, isFalse);
      expect(api.recibidas.single['uuid'], uuid);
      expect((await fila())['sync_estado'], 'sincronizado');
      expect(await dao.obtenerPorEnviar(cliente), isEmpty);
      // una segunda pasada no lo vuelve a mandar
      await provider.sincronizarConServidor(cliente);
      expect(api.recibidas, hasLength(1));
    });

    test('cuando el servidor dice que llegó el stock: la suscripción pasa a notificado, suena la campana y sale el aviso', () async {
      await provider.suscribirse(_agotado(), cliente);
      final local = await fila();
      api.notificaciones = [
        {'id': 500, 'uuid': local['id'], 'producto_id': 107, 'talla_id': 1, 'color_id': 5, 'sucursal_id': 1, 'descripcion': 'Falda plisada · Talla S · Negro', 'estado': 'notificado', 'visto': false, 'notificado_en': '2026-11-07T12:00:00Z'},
      ];

      expect(await provider.sincronizarConServidor(cliente), isTrue);

      expect((await fila())['estado'], 'notificado');
      expect(provider.sinVer, 1, reason: 'la campana cuenta los avisos sin ver');
      expect(provider.pendientes, isEmpty);

      final mensajes = await provider.revisarAvisos(cliente);

      expect(mensajes.single, allOf(contains('¡Llegó el producto que esperabas!'), contains('Falda plisada')));
      expect(provider.sinVer, 0);
      await Future<void>.delayed(Duration.zero);
      expect(api.vistas, 1, reason: 'el servidor también los da por vistos');
      expect(await provider.revisarAvisos(cliente), isEmpty); // no se repite
    });

    test('revisarAvisos pregunta primero al servidor: el stock pudo llegar mientras no había red', () async {
      await provider.suscribirse(_agotado(), cliente);
      final local = await fila();
      api.notificaciones = [
        {'id': 500, 'uuid': local['id'], 'producto_id': 107, 'descripcion': 'Falda plisada', 'estado': 'notificado', 'visto': false},
      ];

      final mensajes = await provider.revisarAvisos(cliente);

      expect(mensajes, hasLength(1));
    });

    test('un aviso pedido desde la WEB (u otro dispositivo) también aparece ya notificado', () async {
      api.notificaciones = [
        {'id': 9, 'uuid': null, 'producto_id': 108, 'talla_id': null, 'color_id': null, 'sucursal_id': null, 'nombre_producto': 'Camisa de lino', 'descripcion': 'Camisa de lino', 'estado': 'notificado', 'visto': false, 'notificado_en': '2026-11-07T10:00:00Z', 'fecha': '2026-11-06T10:00:00Z'},
      ];

      final mensajes = await provider.revisarAvisos(cliente);

      expect(mensajes.single, contains('Camisa de lino'));
      expect((await fila())['sync_estado'], 'sincronizado');
    });

    test('un aviso que el servidor ya dio por visto no vuelve a molestar', () async {
      api.notificaciones = [
        {'id': 9, 'uuid': null, 'producto_id': 108, 'descripcion': 'Camisa', 'estado': 'notificado', 'visto': true},
      ];

      expect(await provider.revisarAvisos(cliente), isEmpty);
      expect(provider.sinVer, 0);
    });

    test('si al enviar ya había stock, el servidor responde "notificado" y el aviso llega de una vez', () async {
      api.estadoAlCrear = 'notificado';
      api.notificaciones = [];

      await provider.suscribirse(_agotado(), cliente);

      expect((await fila())['estado'], 'notificado');
      expect(provider.sinVer, 1);
    });

    test('un rechazo del servidor (4xx) se anota y no se reintenta', () async {
      api.rechazarCon = 404;
      await provider.suscribirse(_agotado(), cliente);
      expect((await fila())['sync_estado'], 'rechazado');

      api.rechazarCon = null;
      await provider.sincronizarConServidor(cliente);

      expect(api.recibidas, isEmpty, reason: 'lo rechazado no se vuelve a enviar');
    });

    test('la espera al servidor tiene tope: un servidor que no responde no congela la app', () async {
      final lento = _ApiLenta();
      final p = SuscripcionesProvider(
        dao: dao,
        remoto: SuscripcionesRemotas(api: lento, dao: dao),
        esperaServidor: const Duration(milliseconds: 50),
      );

      expect(await p.suscribirse(_agotado(producto: 110), cliente), isTrue);

      expect(p.mensaje, contains('Sin conexión'));
      expect((await (await appDb.database)!.query(Schema.tablaSuscripcionesStock)).single['sync_estado'], 'pendiente');
    });
  });

  group('migración v5 → v6', () {
    late String ruta;

    setUp(() => ruta = '${Directory.systemTemp.path}${Platform.pathSeparator}smartlook_mig6_${DateTime.now().microsecondsSinceEpoch}.db');

    tearDown(() async {
      for (final sufijo in ['', '-journal', '-wal', '-shm']) {
        final f = File('$ruta$sufijo');
        if (await f.exists()) await f.delete();
      }
    });

    test('los avisos que ya existían se conservan, quedan pendientes de enviar y la tabla gana las columnas nuevas', () async {
      // base v5: igual que la actual pero sin las columnas de sincronización
      final ddlV5 = [
        for (final s in Schema.ddl)
          s.contains('CREATE TABLE suscripciones_stock') ? s.replaceFirst(RegExp(r",\s*sync_estado[\s\S]*?id_servidor INTEGER"), '') : s,
      ];
      final v5 = await openDatabase(
        ruta,
        version: 5,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) async {
          for (final s in ddlV5) {
            await db.execute(s);
          }
        },
      );
      await v5.insert('suscripciones_stock', {
        'id': 'a1', 'cliente_id': cliente, 'producto_id': 107, 'descripcion': 'Falda plisada', 'fecha_suscripcion': '2026-11-01T10:00:00Z',
      });
      await v5.close();

      final db = await AppDatabase.abrir(ruta); // → onUpgrade(5, 6)
      final nuevo = AppDatabase.conBaseDeDatos(db);
      addTearDown(nuevo.cerrar);

      final fila = (await db.query('suscripciones_stock')).single;
      expect((fila['id'], fila['sync_estado'], fila['id_servidor']), ('a1', 'pendiente', null));
      expect(await SuscripcionStockDao(appDatabase: nuevo).obtenerPorEnviar(cliente), hasLength(1));
      expect(Sqflite.firstIntValue(await db.rawQuery('PRAGMA foreign_keys')), 1);
      await expectLater(db.update('suscripciones_stock', {'sync_estado': 'inventado'}), throwsA(anything)); // el CHECK vigila
    });
  });

  group('campana en el catálogo', () {
    Future<void> montar(WidgetTester tester, int sinVer) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<CatalogoOfflineProvider>(create: (_) => _CatalogoFalso()),
            ChangeNotifierProvider<SuscripcionesProvider>(create: (_) => _SuscripcionesFalso(sinVer)),
            ChangeNotifierProvider<AuthProvider>(create: (_) => _AuthFalso()),
            ChangeNotifierProvider<ConectividadProvider>(create: (_) => ConectividadProvider(cambios: const Stream.empty(), consultar: () async => [])),
            Provider<SyncService>(create: (_) => _SyncFalso()),
          ],
          child: const MaterialApp(home: CatalogoOfflineScreen()),
        ),
      );
      await tester.pump();
    }

    testWidgets('si llegó algo de lo que esperaba, la campana muestra cuántos avisos hay sin ver', (tester) async {
      await montar(tester, 2);

      expect(find.byKey(const Key('campana_avisos')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('campana_avisos')), matching: find.text('2')), findsOneWidget);
      expect(find.byIcon(Icons.notifications_active), findsOneWidget);
    });

    testWidgets('sin avisos la campana está tranquila (sin número)', (tester) async {
      await montar(tester, 0);

      expect(find.byIcon(Icons.notifications_none), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('campana_avisos')), matching: find.text('0')), findsNothing);
    });
  });
}

class _ApiLenta implements ApiSuscripciones {
  @override
  Future<Map<String, dynamic>> crear(Map<String, dynamic> cuerpo) => Completer<Map<String, dynamic>>().future; // nunca responde

  @override
  Future<List<Map<String, dynamic>>> misNotificaciones() => Completer<List<Map<String, dynamic>>>().future;

  @override
  Future<void> marcarVistas() async {}
}

class _CatalogoFalso extends CatalogoOfflineProvider {
  @override
  List<CatalogoItem> get productos => const [];

  @override
  bool get soportado => false;

  @override
  Future<void> cargar() async {}
}

class _SuscripcionesFalso extends SuscripcionesProvider {
  _SuscripcionesFalso(this._sinVer);

  final int _sinVer;

  @override
  int get sinVer => _sinVer;

  @override
  bool get soportado => false;

  @override
  Future<void> cargar(int clienteId) async {}
}

class _SyncFalso implements SyncService {
  @override
  Stream<ResultadoSync> get alSincronizarAutomaticamente => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _AuthFalso extends ChangeNotifier implements AuthProvider {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
