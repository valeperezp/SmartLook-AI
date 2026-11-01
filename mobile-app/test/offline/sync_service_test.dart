import 'package:flutter_test/flutter_test.dart';
import 'package:smartlook_mobile/core/database/app_database.dart';
import 'package:smartlook_mobile/features/offline/data/catalogo_local_dao.dart';
import 'package:smartlook_mobile/features/offline/data/sync_queue_dao.dart';
import 'package:smartlook_mobile/features/offline/services/sync_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Map<String, dynamic> _operacion({int? cajeroId = 7}) => {
      'sucursal_id': 1,
      'cajero_id': cajeroId,
      'items': [
        {
          'producto_id': 101,
          'talla_id': 2,
          'color_id': 1,
          'nombre_producto': 'Camiseta básica',
          'cantidad': 2,
          'precio_unitario_centavos': 1999,
        },
        {'producto_id': 103, 'nombre_producto': 'Jean slim', 'cantidad': 1, 'precio_unitario_centavos': 5999},
      ],
    };

void main() {
  late AppDatabase appDb;
  late SyncQueueDao cola;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    appDb = AppDatabase.conBaseDeDatos(await AppDatabase.abrir(inMemoryDatabasePath));
    cola = SyncQueueDao(appDatabase: appDb);
  });

  tearDown(() => appDb.cerrar());

  Future<void> encolar(String uuid, {String tipo = 'VENTA_CONTADO'}) {
    final reserva = tipo == 'RESERVA_CLIENTE';
    return cola.guardarOperacionOffline(_operacion(cajeroId: reserva ? null : 7), uuid, tipo, reserva ? 55 : null);
  }

  Future<List<Map<String, Object?>>> estados() async => (await appDb.database)!.rawQuery(
        'SELECT q.operacion_uuid AS uuid, q.estado AS cola, o.estado AS op, o.id_servidor, q.intentos, q.ultimo_error '
        'FROM sync_queue q JOIN operaciones_locales o ON o.uuid = q.operacion_uuid ORDER BY q.operacion_uuid',
      );

  SyncService servicio({
    bool red = true,
    EnviarLote? enviar,
    double Function()? sorteo,
  }) =>
      SyncService(colaDao: cola, hayRed: () async => red, enviar: enviar, sorteo: sorteo);

  test('sin red no toca la cola ni envía nada', () async {
    await encolar('a');
    var envios = 0;
    final r = await servicio(
      red: false,
      enviar: (_) async {
        envios++;
        return {};
      },
    ).sincronizarPendientes();

    expect(r.sinRed, isTrue);
    expect(r.resumen, contains('Sin conexión'));
    expect(envios, 0);
    final est = (await estados()).single;
    expect(est['cola'], 'pendiente');
    expect(est['intentos'], 0);
  });

  test('sin pendientes no envía', () async {
    final r = await servicio(enviar: (_) async => fail('no debe enviar')).sincronizarPendientes();
    expect(r.total, 0);
    expect(r.resumen, 'No hay operaciones pendientes.');
  });

  test('el lote lleva uuid local, tipo y cliente/cajero; ok y conflict actualizan ambas tablas', () async {
    await encolar('a');
    await encolar('b', tipo: 'RESERVA_CLIENTE');
    await encolar('c');
    Map<String, dynamic>? lote;

    final r = await servicio(
      enviar: (l) async {
        lote = l;
        return {
          'resultados': [
            {'uuid': 'a', 'status': 'ok', 'id_servidor': 11},
            {'uuid': 'b', 'status': 'ok', 'id_servidor': 12},
            {'uuid': 'c', 'status': 'conflict', 'message': 'Stock insuficiente'},
          ],
        };
      },
    ).sincronizarPendientes();

    expect((r.sincronizadas, r.rechazadas, r.fallidas), (2, 1, 0));
    expect(r.resumen, '2 sincronizadas, 1 rechazada');

    final ops = lote!['operaciones'] as List;
    expect(ops.map((o) => o['uuid']), ['a', 'b', 'c']);
    expect(ops[0]['tipo_operacion'], 'VENTA_CONTADO');
    expect(ops[0]['cajero_id'], 7);
    expect(ops[1]['tipo_operacion'], 'RESERVA_CLIENTE');
    expect(ops[1]['cliente_id'], 55);
    expect(ops[1]['cajero_id'], isNull);
    expect(ops[0]['total_centavos'], 2 * 1999 + 5999);
    expect((ops[0]['items'] as List), hasLength(2));
    expect((ops[0]['items'] as List).first, containsPair('producto_id', 101));

    final est = await estados();
    expect(est[0], containsPair('cola', 'sincronizado'));
    expect(est[0], containsPair('op', 'sincronizada'));
    expect(est[0], containsPair('id_servidor', 11));
    expect(est[2], containsPair('cola', 'rechazado'));
    expect(est[2], containsPair('op', 'rechazada'));
    expect(est[2], containsPair('ultimo_error', 'Stock insuficiente'));
    expect(await cola.obtenerOperacionesPendientes(), isEmpty);
  });

  test('servidor simulado: sorteo bajo = conflict, alto = ok', () async {
    await encolar('a');
    await encolar('b');
    final sorteos = [0.1, 0.5]; // a: conflict (< 0.2), b: ok

    final r = await servicio(sorteo: () => sorteos.removeAt(0)).sincronizarPendientes();

    expect((r.sincronizadas, r.rechazadas), (1, 1));
    final est = await estados();
    expect(est[0], containsPair('cola', 'rechazado'));
    expect(est[1], containsPair('cola', 'sincronizado'));
    expect(est[1]['id_servidor'], isNotNull); // el CHECK exige id_servidor al sincronizar
  });

  test('si el envío falla quedan pendientes, con el intento contado', () async {
    await encolar('a');
    final r = await servicio(enviar: (_) async => throw Exception('timeout')).sincronizarPendientes();

    expect(r.fallidas, 1);
    final est = (await estados()).single;
    expect(est['cola'], 'pendiente');
    expect(est['intentos'], 1);
    expect(est['ultimo_error'], contains('timeout'));
    expect(await cola.obtenerOperacionesPendientes(), hasLength(1)); // se reintentará
  });

  test('respuesta incompleta o incomprensible: vuelven a pendiente', () async {
    await encolar('a');
    await encolar('b');
    final r = await servicio(
      enviar: (_) async => {
        'resultados': [
          {'uuid': 'a', 'status': 'ok'}, // ok sin id_servidor; 'b' ni aparece
        ],
      },
    ).sincronizarPendientes();

    expect(r.fallidas, 2);
    expect((await estados()).map((e) => e['cola']), ['pendiente', 'pendiente']);
  });

  test('una operación ya cerrada no se puede cerrar otra vez', () async {
    await encolar('a');
    await cola.marcarRechazada('a', 'x');
    await expectLater(cola.marcarSincronizada('a', idServidor: 1), throwsStateError);
    expect((await estados()).single['op'], 'rechazada');
  });

  test('recupera lo que quedó en_proceso por un cierre a mitad de envío', () async {
    await encolar('a');
    final fila = (await cola.obtenerOperacionesPendientes()).single;
    await cola.marcarEnProceso([fila['id'] as String]);
    expect(await cola.obtenerOperacionesPendientes(), isEmpty);

    final r = await servicio(sorteo: () => 0.9).sincronizarPendientes();
    expect(r.sincronizadas, 1);
  });

  test('conflict: devuelve el stock descontado; ok: lo deja descontado', () async {
    final catalogo = CatalogoLocalDao(appDatabase: appDb);
    await catalogo.guardarLoteCatalogo([
      {
        'inventario_id': 1, 'sucursal_id': 1, 'producto_id': 101, 'talla_id': 2, 'color_id': 1,
        'nombre_producto': 'Camiseta básica', 'precio_centavos': 1999, 'cantidad_disponible': 10,
      },
      {
        'inventario_id': 2, 'sucursal_id': 1, 'producto_id': 103, 'talla_id': null, 'color_id': null,
        'nombre_producto': 'Jean slim', 'precio_centavos': 5999, 'cantidad_disponible': 5,
      },
    ]);
    Future<int> stock(int productoId) async => (await catalogo.obtenerProductos())
        .firstWhere((p) => p['producto_id'] == productoId)['cantidad_disponible'] as int;
    Map<String, dynamic> venta(int inventarioId, int productoId, int? talla, int? color, int cantidad) => {
          'sucursal_id': 1,
          'cajero_id': 7,
          'items': [
            {
              'inventario_id': inventarioId, 'producto_id': productoId, 'talla_id': talla, 'color_id': color,
              'nombre_producto': 'x', 'cantidad': cantidad, 'precio_unitario_centavos': 100,
            },
          ],
        };
    await cola.guardarOperacionOffline(venta(1, 101, 2, 1, 3), 'va', 'VENTA_CONTADO', null, descontarStockLocal: true);
    await cola.guardarOperacionOffline(venta(2, 103, null, null, 2), 'vb', 'VENTA_CONTADO', null, descontarStockLocal: true);
    expect(await stock(101), 7);
    expect(await stock(103), 3);

    await servicio(
      enviar: (_) async => {
        'resultados': [
          {'uuid': 'va', 'status': 'conflict', 'message': 'Stock insuficiente'},
          {'uuid': 'vb', 'status': 'ok', 'id_servidor': 5},
        ],
      },
    ).sincronizarPendientes();

    expect(await stock(101), 10); // rechazada: stock devuelto
    expect(await stock(103), 3); // aceptada: sigue descontado (variante sin talla ni color incluida)
  });

  test('dos sincronizaciones simultáneas: la segunda no hace nada', () async {
    await encolar('a');
    final sync = servicio(sorteo: () => 0.9);
    final resultados = await Future.wait([sync.sincronizarPendientes(), sync.sincronizarPendientes()]);
    expect(resultados.where((r) => r.yaEnCurso), hasLength(1));
    expect(resultados.fold<int>(0, (s, r) => s + r.sincronizadas), 1);
  });
}
