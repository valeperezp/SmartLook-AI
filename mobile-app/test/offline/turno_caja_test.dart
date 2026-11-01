import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartlook_mobile/core/database/app_database.dart';
import 'package:smartlook_mobile/core/database/schema.dart';
import 'package:smartlook_mobile/features/offline/data/catalogo_local_dao.dart';
import 'package:smartlook_mobile/features/offline/data/sync_queue_dao.dart';
import 'package:smartlook_mobile/features/offline/data/turno_caja_dao.dart';
import 'package:smartlook_mobile/features/offline/providers/turno_caja_provider.dart';
import 'package:smartlook_mobile/features/offline/providers/venta_offline_provider.dart';
import 'package:smartlook_mobile/features/offline/services/sync_service.dart';
import 'package:sqflite/sqflite.dart' show Sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'schema_v1_fixture.dart';

Map<String, dynamic> _venta({int cajeroId = 7, int cantidad = 1, int precio = 1000}) => {
      'sucursal_id': 1,
      'cajero_id': cajeroId,
      'items': [
        {'producto_id': 101, 'nombre_producto': 'Camiseta', 'cantidad': cantidad, 'precio_unitario_centavos': precio},
      ],
    };

void main() {
  late AppDatabase appDb;
  late SyncQueueDao cola;
  late TurnoCajaDao turnos;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    appDb = AppDatabase.conBaseDeDatos(await AppDatabase.abrir(inMemoryDatabasePath));
    cola = SyncQueueDao(appDatabase: appDb);
    turnos = TurnoCajaDao(appDatabase: appDb);
  });

  tearDown(() => appDb.cerrar());

  Future<int> contar(String tabla, [String? donde]) async {
    final db = (await appDb.database)!;
    return Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM $tabla ${donde ?? ''}'))!;
  }

  Future<void> vender(String uuid, String? turno, {int cantidad = 1, int precio = 1000, int cajeroId = 7}) {
    return cola.guardarOperacionOffline(
      _venta(cajeroId: cajeroId, cantidad: cantidad, precio: precio),
      uuid,
      Schema.tipoVentaContado,
      null,
      turnoUuid: turno,
    );
  }

  group('apertura', () {
    test('abre un turno con el monto inicial y estado abierto', () async {
      final id = await turnos.abrirTurno(7, 1, 5000);

      final t = (await turnos.obtenerTurnoAbierto(7, 1))!;
      expect(t['id'], id);
      expect(t['monto_inicial_centavos'], 5000);
      expect(t['estado'], 'abierto');
      expect(t['monto_esperado_centavos'], isNull);
      expect(t['fecha_cierre'], isNull);
      expect(await turnos.obtenerTurnoAbierto(8, 1), isNull); // otro cajero: nada
    });

    test('no se puede abrir otro turno estando uno abierto (mismo cajero y sucursal)', () async {
      final primero = await turnos.abrirTurno(7, 1, 5000);
      await expectLater(
        turnos.abrirTurno(7, 1, 100),
        throwsA(isA<TurnoYaAbierto>().having((e) => e.turnoUuid, 'turnoUuid', primero)),
      );
      expect(await contar(Schema.tablaTurnosCaja), 1);

      // otro cajero, u otra sucursal, sí pueden
      await turnos.abrirTurno(8, 1, 0);
      await turnos.abrirTurno(7, 2, 0);
      expect(await contar(Schema.tablaTurnosCaja), 3);
    });

    test('la base también lo impide (índice único parcial), aunque se salte el DAO', () async {
      await turnos.abrirTurno(7, 1, 0);
      final db = (await appDb.database)!;
      await expectLater(
        db.insert(Schema.tablaTurnosCaja, {
          'id': 'otro', 'cajero_id': 7, 'sucursal_id': 1, 'monto_inicial_centavos': 0,
          'fecha_apertura': DateTime.now().toIso8601String(),
        }),
        throwsA(anything),
      );
    });

    test('con el turno cerrado se puede abrir uno nuevo; un monto negativo se rechaza', () async {
      final id = await turnos.abrirTurno(7, 1, 0);
      await turnos.cerrarTurno(id, 0);
      await turnos.abrirTurno(7, 1, 2000);
      expect(await contar(Schema.tablaTurnosCaja), 2);
      await expectLater(turnos.abrirTurno(9, 1, -1), throwsArgumentError);
    });
  });

  group('vínculo de las ventas con el turno', () {
    test('una venta con turnoUuid queda vinculada; las reservas no tienen turno', () async {
      final turno = await turnos.abrirTurno(7, 1, 0);
      await vender('v1', turno);
      await cola.guardarOperacionOffline(_venta(), 'r1', Schema.tipoReservaCliente, 55);

      final db = (await appDb.database)!;
      final filas = await db.query(Schema.tablaOperaciones, columns: ['uuid', 'turno_uuid'], orderBy: 'uuid');
      expect(filas[0], {'uuid': 'r1', 'turno_uuid': null});
      expect(filas[1], {'uuid': 'v1', 'turno_uuid': turno});
    });

    test('una reserva no puede vincularse a un turno', () async {
      final turno = await turnos.abrirTurno(7, 1, 0);
      await expectLater(
        cola.guardarOperacionOffline(_venta(), 'r2', Schema.tipoReservaCliente, 55, turnoUuid: turno),
        throwsArgumentError,
      );
      expect(await contar(Schema.tablaOperaciones), 0);
    });

    test('no se vende contra un turno inexistente ni cerrado, y no queda nada a medias', () async {
      await expectLater(vender('v1', 'no-existe'), throwsA(isA<TurnoNoAbierto>()));

      final turno = await turnos.abrirTurno(7, 1, 0);
      await turnos.cerrarTurno(turno, 0);
      await expectLater(vender('v2', turno), throwsA(isA<TurnoNoAbierto>()));

      expect(await contar(Schema.tablaOperaciones), 0);
      expect(await contar(Schema.tablaOperacionesItems), 0);
      expect(await contar(Schema.tablaSyncQueue, "WHERE tipo_operacion != 'CIERRE_CAJA'"), 0);
    });
  });

  group('monto esperado', () {
    test('monto inicial + ventas del turno; ignora reservas, otros turnos y rechazadas', () async {
      final turno = await turnos.abrirTurno(7, 1, 5000);
      expect(await turnos.calcularMontoEsperado(turno), 5000); // sin ventas

      await vender('v1', turno, cantidad: 2, precio: 1500); // 3000
      await vender('v2', turno, precio: 2000); // 2000
      await vender('v3', turno, precio: 700); // 700: se rechazará
      await cola.guardarOperacionOffline(_venta(precio: 9999), 'r1', Schema.tipoReservaCliente, 55);
      final otro = await turnos.abrirTurno(8, 1, 100);
      await vender('x1', otro, precio: 4000, cajeroId: 8);
      await cola.marcarRechazada('v3', 'Stock insuficiente');

      expect(await turnos.calcularMontoEsperado(turno), 5000 + 3000 + 2000);
      expect(await turnos.calcularMontoEsperado(otro), 100 + 4000);
      expect((await turnos.listarVentasDelTurno(turno)).map((v) => v['uuid']), unorderedEquals(['v1', 'v2']));
    });

    test('las ventas ya sincronizadas también cuentan', () async {
      final turno = await turnos.abrirTurno(7, 1, 0);
      await vender('v1', turno, precio: 2500);
      await cola.marcarSincronizada('v1', idServidor: 10);
      expect(await turnos.calcularMontoEsperado(turno), 2500);
    });
  });

  group('cierre y arqueo', () {
    test('con faltante: diferencia negativa', () async {
      final turno = await turnos.abrirTurno(7, 1, 5000);
      await vender('v1', turno, precio: 3000);

      final r = await turnos.cerrarTurno(turno, 7500, confirmarPendientes: true);

      expect((r.esperadoCentavos, r.realCentavos, r.diferenciaCentavos), (8000, 7500, -500));
    });

    test('con sobrante: diferencia positiva', () async {
      final turno = await turnos.abrirTurno(7, 1, 5000);
      await vender('v1', turno, precio: 3000);

      final r = await turnos.cerrarTurno(turno, 8200, confirmarPendientes: true);

      expect(r.diferenciaCentavos, 200);
    });

    test('exacto: diferencia cero; el turno queda cerrado con todos sus datos', () async {
      final turno = await turnos.abrirTurno(7, 1, 1000);
      final r = await turnos.cerrarTurno(turno, 1000);
      expect(r.diferenciaCentavos, 0);

      final t = (await turnos.obtenerTurno(turno))!;
      expect(t['estado'], 'cerrado');
      expect(t['monto_esperado_centavos'], 1000);
      expect(t['monto_real_centavos'], 1000);
      expect(t['diferencia_centavos'], 0);
      expect(t['fecha_cierre'], isNotNull);
      expect(await turnos.obtenerTurnoAbierto(7, 1), isNull);
    });

    test('no se puede cerrar dos veces ni con monto negativo', () async {
      final turno = await turnos.abrirTurno(7, 1, 0);
      await expectLater(turnos.cerrarTurno(turno, -1), throwsArgumentError);
      await turnos.cerrarTurno(turno, 0);
      await expectLater(turnos.cerrarTurno(turno, 0), throwsA(isA<TurnoNoAbierto>()));
      await expectLater(turnos.cerrarTurno('no-existe', 0), throwsA(isA<TurnoNoAbierto>()));
      expect(await contar(Schema.tablaSyncQueue, "WHERE tipo_operacion = 'CIERRE_CAJA'"), 1);
    });

    test('encola un CIERRE_CAJA pendiente con el arqueo y las ventas incluidas', () async {
      final turno = await turnos.abrirTurno(7, 1, 5000);
      await vender('v1', turno, precio: 3000);
      await vender('v2', turno, precio: 500);
      await cola.marcarRechazada('v2', 'x'); // rechazada: no entra al cierre
      await cola.marcarSincronizada('v1', idServidor: 1);

      await turnos.cerrarTurno(turno, 8000);

      final db = (await appDb.database)!;
      final c = (await db.query(Schema.tablaSyncQueue, where: "tipo_operacion = 'CIERRE_CAJA'")).single;
      expect(c['estado'], 'pendiente');
      expect(c['turno_uuid'], turno);
      expect(c['operacion_uuid'], isNull);
      final payload = await cola.obtenerOperacionesPendientes();
      expect(payload, hasLength(1));
      expect(payload.single['payload_json'] as String, allOf(contains('"monto_esperado_centavos":8000'), contains('"diferencia_centavos":0'), contains('"v1"'), isNot(contains('"v2"'))));
    });

    test('con ventas sin sincronizar exige confirmación y no cambia nada hasta confirmarla', () async {
      final turno = await turnos.abrirTurno(7, 1, 0);
      await vender('v1', turno);
      await vender('v2', turno);
      await cola.marcarSincronizada('v2', idServidor: 2);

      await expectLater(
        turnos.cerrarTurno(turno, 1000),
        throwsA(isA<OperacionesPendientesEnTurno>().having((e) => e.cantidad, 'cantidad', 1)),
      );
      expect((await turnos.obtenerTurno(turno))!['estado'], 'abierto');
      expect(await contar(Schema.tablaSyncQueue, "WHERE tipo_operacion = 'CIERRE_CAJA'"), 0);

      await turnos.cerrarTurno(turno, 2000, confirmarPendientes: true);
      expect((await turnos.obtenerTurno(turno))!['estado'], 'cerrado');
    });

    test('sin ventas pendientes (todas sincronizadas o rechazadas) cierra sin advertencia', () async {
      final turno = await turnos.abrirTurno(7, 1, 0);
      await vender('v1', turno);
      await vender('v2', turno);
      await cola.marcarSincronizada('v1', idServidor: 1);
      await cola.marcarRechazada('v2', 'x');
      await turnos.cerrarTurno(turno, 1000);
    });
  });

  group('TurnoCajaProvider y la venta del POS', () {
    late TurnoCajaProvider provider;

    setUp(() => provider = TurnoCajaProvider(dao: turnos));

    test('validarMonto rechaza vacío, texto y negativos', () {
      expect(TurnoCajaProvider.validarMonto(''), isNotNull);
      expect(TurnoCajaProvider.validarMonto('abc'), isNotNull);
      expect(TurnoCajaProvider.validarMonto('-5'), isNotNull);
      expect(TurnoCajaProvider.validarMonto('1.234'), isNotNull);
      expect(TurnoCajaProvider.validarMonto('100'), isNull);
      expect(TurnoCajaProvider.validarMonto('100,50'), isNull);
    });

    test('abrir con un monto inválido no crea el turno', () async {
      for (final malo in ['', 'abc', '-5']) {
        expect(await provider.abrir(cajeroId: 7, sucursalId: 1, montoTexto: malo), isFalse);
      }
      expect(provider.hayTurnoAbierto, isFalse);
      expect(await contar(Schema.tablaTurnosCaja), 0);
    });

    test('flujo completo: abrir, vender por el POS, ver el esperado y cerrar con la advertencia', () async {
      expect(await provider.abrir(cajeroId: 7, sucursalId: 1, montoTexto: '50'), isTrue);
      expect(provider.hayTurnoAbierto, isTrue);
      expect(await provider.abrir(cajeroId: 7, sucursalId: 1, montoTexto: '10'), isFalse); // ya hay una
      expect(provider.error, contains('abierta'));

      final catalogo = CatalogoLocalDao(appDatabase: appDb);
      final pos = VentaOfflineProvider(catalogoDao: catalogo, colaDao: cola);
      await pos.cargarDatosMock(1);
      pos.agregarProducto(pos.productos.firstWhere((p) => p.productoId == 101)); // $19.99
      expect(await pos.procesarVenta(cajeroId: 7, sucursalId: 1, turnoUuid: provider.turno!.id), isTrue);

      await provider.refrescar();
      expect(provider.ventas, hasLength(1));
      expect(provider.esperadoCentavos, 5000 + 1999);
      expect(provider.pendientesSync, 1);

      expect(await provider.cerrar('abc'), ResultadoCierre.error);
      expect(await provider.cerrar('68.50'), ResultadoCierre.requiereConfirmacion); // venta sin sincronizar
      expect(provider.pendientesAlCerrar, 1);
      expect(provider.hayTurnoAbierto, isTrue);

      expect(await provider.cerrar('68.50', confirmarPendientes: true), ResultadoCierre.cerrado);
      expect(provider.hayTurnoAbierto, isFalse);
      expect(provider.ultimoCierre!.diferenciaCentavos, 6850 - 6999); // faltante de $1.49
    });

    test('vender sin pasar turno sigue funcionando (queda sin turno)', () async {
      final catalogo = CatalogoLocalDao(appDatabase: appDb);
      final pos = VentaOfflineProvider(catalogoDao: catalogo, colaDao: cola);
      await pos.cargarDatosMock(1);
      pos.agregarProducto(pos.productos.first);
      expect(await pos.procesarVenta(cajeroId: 7, sucursalId: 1), isTrue);
      expect(await contar(Schema.tablaOperaciones, 'WHERE turno_uuid IS NULL'), 1);
    });

    test('vender contra un turno ya cerrado muestra el aviso y no guarda', () async {
      final turno = await turnos.abrirTurno(7, 1, 0);
      await turnos.cerrarTurno(turno, 0);
      final pos = VentaOfflineProvider(catalogoDao: CatalogoLocalDao(appDatabase: appDb), colaDao: cola);
      await pos.cargarDatosMock(1);
      pos.agregarProducto(pos.productos.first);

      expect(await pos.procesarVenta(cajeroId: 7, sucursalId: 1, turnoUuid: turno), isFalse);
      expect(pos.ultimoMensaje, contains('caja'));
      expect(await contar(Schema.tablaOperaciones), 0);
    });
  });

  group('sincronización del cierre de caja', () {
    SyncService servicio({EnviarLote? enviar, double Function()? sorteo}) => SyncService(
          colaDao: cola,
          turnoDao: turnos,
          hayRed: () async => true,
          enviar: enviar,
          sorteo: sorteo ?? () => 0.9,
        );

    test('las ventas viajan primero y el cierre después; el turno queda sincronizado', () async {
      final turno = await turnos.abrirTurno(7, 1, 1000);
      await vender('v1', turno);
      await turnos.cerrarTurno(turno, 2000, confirmarPendientes: true);
      final lotes = <Map<String, dynamic>>[];

      final r = await servicio(
        enviar: (lote) async {
          lotes.add(lote);
          return {
            'resultados': [
              for (final o in (lote['operaciones'] as List? ?? const [])) {'uuid': o['uuid'], 'status': 'ok', 'id_servidor': 5},
              for (final c in (lote['cierres_caja'] as List? ?? const [])) {'uuid': c['uuid'], 'status': 'ok', 'id_servidor': 77},
            ],
          };
        },
      ).sincronizarPendientes();

      expect(r.sincronizadas, 2);
      expect(lotes, hasLength(2));
      expect(lotes[0].containsKey('operaciones'), isTrue);
      expect(lotes[1]['cierres_caja'], [
        containsPair('uuid', turno),
      ]);
      expect((lotes[1]['cierres_caja'] as List).single['monto_esperado_centavos'], 2000);
      final t = (await turnos.obtenerTurno(turno))!;
      expect(t['estado'], 'sincronizado');
      expect(t['id_servidor'], 77);
      expect(await cola.obtenerOperacionesPendientes(), isEmpty);
    });

    test('con el servidor simulado el cierre siempre se acepta', () async {
      final turno = await turnos.abrirTurno(7, 1, 0);
      await turnos.cerrarTurno(turno, 0);
      final r = await servicio(sorteo: () => 0.0).sincronizarPendientes(); // sorteo "conflict" no aplica a cierres
      expect(r.sincronizadas, 1);
      expect((await turnos.obtenerTurno(turno))!['estado'], 'sincronizado');
    });

    test('si una venta del turno no se pudo enviar, el cierre espera', () async {
      final turno = await turnos.abrirTurno(7, 1, 0);
      await vender('v1', turno);
      await turnos.cerrarTurno(turno, 1000, confirmarPendientes: true);

      var llamada = 0;
      final r1 = await servicio(
        enviar: (lote) async {
          llamada++;
          if (lote.containsKey('operaciones')) throw Exception('timeout');
          fail('el cierre no debe enviarse con ventas del turno sin resolver');
        },
      ).sincronizarPendientes();
      expect(r1.fallidas, 1);
      expect(llamada, 1);
      expect((await turnos.obtenerTurno(turno))!['estado'], 'cerrado');

      // la próxima vez todo sale bien
      final r2 = await servicio().sincronizarPendientes();
      expect(r2.sincronizadas, 2);
      expect((await turnos.obtenerTurno(turno))!['estado'], 'sincronizado');
    });

    test('un cierre rechazado queda marcado con el motivo y el turno sigue cerrado', () async {
      final turno = await turnos.abrirTurno(7, 1, 0);
      await turnos.cerrarTurno(turno, 0);

      await servicio(
        enviar: (lote) async => {
          'resultados': [
            {'uuid': turno, 'status': 'conflict', 'message': 'Turno ya cerrado en el servidor'},
          ],
        },
      ).sincronizarPendientes();

      final db = (await appDb.database)!;
      final c = (await db.query(Schema.tablaSyncQueue, where: "tipo_operacion = 'CIERRE_CAJA'")).single;
      expect(c['estado'], 'rechazado');
      expect(c['ultimo_error'], contains('ya cerrado'));
      expect((await turnos.obtenerTurno(turno))!['estado'], 'cerrado');
    });
  });

  group('migración v1 → v2', () {
    late String ruta;

    setUp(() {
      ruta = '${Directory.systemTemp.path}${Platform.pathSeparator}smartlook_migracion_${DateTime.now().microsecondsSinceEpoch}.db';
    });

    tearDown(() async {
      for (final sufijo in ['', '-journal', '-wal', '-shm']) {
        final f = File('$ruta$sufijo');
        if (await f.exists()) await f.delete();
      }
    });

    test('conserva los datos y habilita turnos y CIERRE_CAJA', () async {
      // base v1 con una venta ya encolada
      final v1 = await openDatabase(
        ruta,
        version: 1,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) async {
          for (final ddl in ddlV1) {
            await db.execute(ddl);
          }
        },
      );
      await v1.insert('operaciones_locales', {
        'uuid': 'vieja', 'tipo_operacion': 'VENTA_CONTADO', 'sucursal_id': 1, 'cajero_id': 7,
        'total_centavos': 4200, 'fecha': '2026-10-01T10:00:00Z',
      });
      await v1.insert('sync_queue', {
        'id': 'q1', 'tipo_operacion': 'VENTA_CONTADO', 'operacion_uuid': 'vieja', 'payload_json': '{}',
        'estado': 'pendiente', 'intentos': 2, 'ultimo_error': 'timeout', 'fecha_creacion': '2026-10-01T10:00:00Z',
      });
      await v1.close();

      // se reabre con el esquema actual → onUpgrade
      final db = await AppDatabase.abrir(ruta);
      final nuevo = AppDatabase.conBaseDeDatos(db);
      addTearDown(nuevo.cerrar);

      final op = (await db.query('operaciones_locales')).single;
      expect(op['uuid'], 'vieja');
      expect(op['total_centavos'], 4200);
      expect(op['turno_uuid'], isNull);
      final q = (await db.query('sync_queue')).single;
      expect((q['id'], q['intentos'], q['ultimo_error'], q['estado']), ('q1', 2, 'timeout', 'pendiente'));
      expect(Sqflite.firstIntValue(await db.rawQuery('PRAGMA foreign_keys')), 1);

      // y ya funciona lo nuevo
      final dao = TurnoCajaDao(appDatabase: nuevo);
      final turno = await dao.abrirTurno(7, 1, 0);
      await SyncQueueDao(appDatabase: nuevo).guardarOperacionOffline(_venta(), 'nueva', Schema.tipoVentaContado, null, turnoUuid: turno);
      await dao.cerrarTurno(turno, 1000, confirmarPendientes: true);
      expect(Sqflite.firstIntValue(await db.rawQuery("SELECT COUNT(*) FROM sync_queue WHERE tipo_operacion = 'CIERRE_CAJA'")), 1);
    });

    test('la base migrada queda con las mismas columnas que una base nueva', () async {
      final v1 = await openDatabase(ruta, version: 1, onCreate: (db, _) async {
        for (final ddl in ddlV1) {
          await db.execute(ddl);
        }
      });
      await v1.close();
      final migrada = await AppDatabase.abrir(ruta);
      addTearDown(migrada.close);
      final fresca = (await appDb.database)!;

      Future<List<String>> columnas(db, String tabla) async =>
          [for (final c in await db.rawQuery('PRAGMA table_info($tabla)')) '${c['name']}:${c['type']}:${c['notnull']}'];
      for (final tabla in ['operaciones_locales', 'sync_queue', 'turnos_caja', 'operaciones_locales_items', 'catalogo_local']) {
        expect(await columnas(migrada, tabla), await columnas(fresca, tabla), reason: tabla);
      }
      final indices = await migrada.rawQuery("SELECT name FROM sqlite_master WHERE type = 'index' AND name LIKE 'ix_%' OR name LIKE 'ux_%'");
      expect(indices.map((i) => i['name']), containsAll(['ux_turno_abierto', 'ix_sync_cola', 'ix_operaciones_turno']));
    });
  });
}
