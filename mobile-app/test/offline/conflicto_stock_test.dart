import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartlook_mobile/core/database/app_database.dart';
import 'package:smartlook_mobile/core/database/schema.dart';
import 'package:smartlook_mobile/features/offline/data/catalogo_local_dao.dart';
import 'package:smartlook_mobile/features/offline/data/devolucion_dao.dart';
import 'package:smartlook_mobile/features/offline/data/sync_queue_dao.dart';
import 'package:smartlook_mobile/features/offline/providers/venta_offline_provider.dart';
import 'package:smartlook_mobile/features/offline/services/sync_service.dart';
import 'package:sqflite/sqflite.dart' show Sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'schema_v1_fixture.dart';

/// CU13 — el servidor responde `en_conflicto`: la venta se hizo, el servidor la guardó SIN stock y un encargado la
/// resuelve desde la web. El móvil la marca `en_conflicto` y NO devuelve el stock local (a diferencia de `conflict`).
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('SyncService ante "en_conflicto"', () {
    late AppDatabase appDb;
    late SyncQueueDao cola;
    late CatalogoLocalDao catalogo;
    late VentaOfflineProvider pos;

    setUp(() async {
      appDb = AppDatabase.conBaseDeDatos(await AppDatabase.abrir(inMemoryDatabasePath));
      cola = SyncQueueDao(appDatabase: appDb);
      catalogo = CatalogoLocalDao(appDatabase: appDb);
      pos = VentaOfflineProvider(catalogoDao: catalogo, colaDao: cola);
      await pos.cargarDatosMock(1);
    });

    tearDown(() => appDb.cerrar());

    Future<int> stock(int productoId) async =>
        (await catalogo.obtenerProductos()).firstWhere((p) => p['producto_id'] == productoId)['cantidad_disponible'] as int;

    Future<String> vender(int productoId, int cantidad) async {
      final item = pos.productos.firstWhere((p) => p.productoId == productoId);
      for (var i = 0; i < cantidad; i++) {
        pos.agregarProducto(item);
      }
      expect(await pos.procesarVenta(cajeroId: 7, sucursalId: 1), isTrue);
      return ((await (await appDb.database)!.query(Schema.tablaOperaciones, orderBy: 'rowid DESC', limit: 1)).single['uuid']) as String;
    }

    /// Servidor que responde a cada operación con los estados de [porUuid] (y cuenta cuántos lotes recibió).
    EnviarLote servidor(Map<String, Map<String, dynamic>> porUuid, {void Function()? alRecibir}) {
      return (lote) async {
        alRecibir?.call();
        return {
          'resultados': [
            for (final op in (lote['operaciones'] as List? ?? const []))
              {'uuid': (op as Map)['uuid'], ...porUuid[op['uuid']]!},
          ],
        };
      };
    }

    test('marca la operación "en_conflicto", guarda el id del servidor y NO devuelve el stock local', () async {
      final antes = await stock(101);
      final uuid = await vender(101, 2);
      expect(await stock(101), antes - 2);

      final r = await SyncService(
        colaDao: cola,
        hayRed: () async => true,
        enviar: servidor({uuid: {'status': 'en_conflicto', 'id_servidor': 77, 'entidad': 'venta', 'message': 'Stock insuficiente en Camiseta Talla M'}}),
      ).sincronizarPendientes();

      expect((r.enConflicto, r.rechazadas, r.sincronizadas, r.fallidas), (1, 0, 0, 0));
      expect(r.resumen, '1 en conflicto (la resuelve el encargado)');
      final db = (await appDb.database)!;
      final cab = (await db.query(Schema.tablaOperaciones)).single;
      expect((cab['estado'], cab['id_servidor']), ('en_conflicto', 77));
      final q = (await db.query(Schema.tablaSyncQueue)).single;
      expect((q['estado'], q['ultimo_error']), ('en_conflicto', 'Stock insuficiente en Camiseta Talla M'));
      expect(await stock(101), antes - 2, reason: 'la venta ya se hizo: el stock local NO se devuelve');
    });

    test('no se vuelve a enviar: la próxima sincronización no la incluye', () async {
      final uuid = await vender(101, 1);
      var lotes = 0;
      final servicio = SyncService(
        colaDao: cola,
        hayRed: () async => true,
        enviar: servidor({uuid: {'status': 'en_conflicto', 'id_servidor': 5}}, alRecibir: () => lotes++),
      );
      await servicio.sincronizarPendientes();

      final segunda = await servicio.sincronizarPendientes();

      expect(lotes, 1);
      expect(segunda.total, 0);
    });

    test('en un lote mixto cada operación sigue su camino (ok, en_conflicto, conflict)', () async {
      final antesJean = await stock(103);
      final ok = await vender(101, 1);
      final enConflicto = await vender(102, 1);
      final rechazada = await vender(103, 2);

      final r = await SyncService(
        colaDao: cola,
        hayRed: () async => true,
        enviar: servidor({
          ok: {'status': 'ok', 'id_servidor': 1},
          enConflicto: {'status': 'en_conflicto', 'id_servidor': 2, 'message': 'Sin stock'},
          rechazada: {'status': 'conflict', 'message': 'Producto ajeno'},
        }),
      ).sincronizarPendientes();

      expect((r.sincronizadas, r.enConflicto, r.rechazadas, r.fallidas), (1, 1, 1, 0));
      final estados = {for (final c in await (await appDb.database)!.query(Schema.tablaOperaciones)) c['uuid']: c['estado']};
      expect(estados, {ok: 'sincronizada', enConflicto: 'en_conflicto', rechazada: 'rechazada'});
      expect(await stock(103), antesJean, reason: 'solo la RECHAZADA devuelve su stock');
    });

    test('"en_conflicto" sin id_servidor también se acepta (queda en_conflicto con id nulo)', () async {
      final uuid = await vender(101, 1);

      await SyncService(colaDao: cola, hayRed: () async => true, enviar: servidor({uuid: {'status': 'en_conflicto'}})).sincronizarPendientes();

      final cab = (await (await appDb.database)!.query(Schema.tablaOperaciones)).single;
      expect((cab['estado'], cab['id_servidor']), ('en_conflicto', null));
    });

    test('una venta en conflicto no admite cambios/devoluciones ni aparece para elegirla', () async {
      final uuid = await vender(101, 1);
      await SyncService(colaDao: cola, hayRed: () async => true, enviar: servidor({uuid: {'status': 'en_conflicto', 'id_servidor': 9}})).sincronizarPendientes();

      final ventas = await DevolucionDao(appDatabase: appDb).buscarVentas(1);

      expect(ventas.where((v) => v['uuid'] == uuid), isEmpty);
    });
  });

  group('migración v4 → v5 (estado "en_conflicto")', () {
    late String ruta;

    setUp(() {
      ruta = '${Directory.systemTemp.path}${Platform.pathSeparator}smartlook_migracion_v5_${DateTime.now().microsecondsSinceEpoch}.db';
    });

    tearDown(() async {
      for (final sufijo in ['', '-journal', '-wal', '-shm']) {
        final f = File('$ruta$sufijo');
        if (await f.exists()) await f.delete();
      }
    });

    test('reconstruye las tablas padre SIN perder ítems, cola ni devoluciones, y admite "en_conflicto"', () async {
      // base v4 con datos: venta con 2 ítems, su cola y un cierre
      final v4 = await openDatabase(
        ruta,
        version: 4,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) async {
          for (final ddl in ddlV1) {
            await db.execute(ddl);
          }
          for (final s in [...Schema.migracionV2, ...Schema.migracionV3, ...Schema.migracionV4]) {
            await db.execute(s);
          }
        },
      );
      await v4.insert('turnos_caja', {'id': 't1', 'cajero_id': 7, 'sucursal_id': 1, 'monto_inicial_centavos': 500, 'fecha_apertura': '2026-10-01T08:00:00Z'});
      await v4.insert('operaciones_locales', {
        'uuid': 'v1', 'tipo_operacion': 'VENTA_CONTADO', 'sucursal_id': 1, 'cajero_id': 7, 'total_centavos': 1800,
        'fecha': '2026-10-01T09:00:00Z', 'turno_uuid': 't1', 'estado': 'sincronizada', 'id_servidor': 12,
      });
      for (final talla in [2, 3]) {
        await v4.insert('operaciones_locales_items', {'operacion_uuid': 'v1', 'producto_id': 101, 'talla_id': talla, 'color_id': 1, 'nombre_producto': 'Camiseta', 'cantidad': 1, 'precio_unitario_centavos': 900});
      }
      await v4.insert('sync_queue', {'id': 'q1', 'tipo_operacion': 'VENTA_CONTADO', 'operacion_uuid': 'v1', 'payload_json': '{"x":1}', 'estado': 'sincronizado', 'intentos': 2, 'fecha_creacion': '2026-10-01T09:00:00Z'});
      await v4.insert('devoluciones_locales', {
        'id': 'd1', 'venta_uuid': 'v1', 'tipo': 'DEVOLUCION', 'cajero_id': 7, 'sucursal_id': 1, 'total_devuelto_centavos': 900,
        'fecha': '2026-10-01T10:00:00Z', 'turno_uuid': 't1',
      });
      await v4.close();

      final db = await AppDatabase.abrir(ruta); // → onUpgrade(4, 5)
      final nuevo = AppDatabase.conBaseDeDatos(db);
      addTearDown(nuevo.cerrar);

      // nada se perdió: ítems (hijos con ON DELETE CASCADE), cola, devolución y la propia venta
      expect(Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM operaciones_locales_items')), 2);
      expect((await db.query('operaciones_locales')).single['id_servidor'], 12);
      expect((await db.query('sync_queue')).single['intentos'], 2);
      expect((await db.query('sync_queue')).single['payload_json'], '{"x":1}');
      expect(Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM devoluciones_locales')), 1);
      // las claves foráneas quedan activas y sin violaciones
      expect(Sqflite.firstIntValue(await db.rawQuery('PRAGMA foreign_keys')), 1);
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);

      // el estado nuevo ya se acepta, en ambas tablas
      await db.update('operaciones_locales', {'estado': 'en_conflicto', 'id_servidor': 12}, where: "uuid = 'v1'");
      await db.update('sync_queue', {'estado': 'en_conflicto'}, where: "id = 'q1'");
      expect((await db.query('operaciones_locales')).single['estado'], 'en_conflicto');
      expect((await db.query('sync_queue')).single['estado'], 'en_conflicto');
      // y la restricción de claves foráneas sigue vigilando: un ítem huérfano falla
      await expectLater(
        db.insert('operaciones_locales_items', {'operacion_uuid': 'no-existe', 'producto_id': 1, 'nombre_producto': 'x', 'cantidad': 1, 'precio_unitario_centavos': 1}),
        throwsA(anything),
      );
    });

    test('una base nueva (v5) admite "en_conflicto" y rechaza estados inventados', () async {
      final db = await AppDatabase.abrir(inMemoryDatabasePath);
      final appDb = AppDatabase.conBaseDeDatos(db);
      addTearDown(appDb.cerrar);
      await db.insert('operaciones_locales', {'uuid': 'a', 'tipo_operacion': 'VENTA_CONTADO', 'sucursal_id': 1, 'cajero_id': 7, 'total_centavos': 1, 'fecha': 'x', 'estado': 'en_conflicto'});

      await expectLater(
        db.insert('operaciones_locales', {'uuid': 'b', 'tipo_operacion': 'VENTA_CONTADO', 'sucursal_id': 1, 'cajero_id': 7, 'total_centavos': 1, 'fecha': 'x', 'estado': 'inventado'}),
        throwsA(anything),
      );
    });
  });
}
