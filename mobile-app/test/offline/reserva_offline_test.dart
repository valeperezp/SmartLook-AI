import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlook_mobile/core/database/app_database.dart';
import 'package:smartlook_mobile/core/database/schema.dart';
import 'package:smartlook_mobile/features/offline/data/catalogo_local_dao.dart';
import 'package:smartlook_mobile/features/offline/data/sync_queue_dao.dart';
import 'package:smartlook_mobile/features/offline/providers/catalogo_offline_provider.dart';
import 'package:smartlook_mobile/features/offline/services/sync_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// CU9 — Registrar reserva offline, de punta a punta:
/// reservar sin red (SQLite `pendiente_sync` + `sync_queue` RESERVA_CLIENTE + stock local descontado)
/// → volver la red → `POST /sync/operaciones` → `sincronizada`.
///
/// Solo usa el código real de la app (provider + DAO + SyncService); el backend es un Dio falso (no se toca ningún servidor).

const _clienteId = 55;

/// Reserva de 1 unidad de la variante [inventarioId], con el formato que arma `CatalogoOfflineProvider.reservarProducto`.
Map<String, dynamic> _reserva({int inventarioId = 1, int cantidad = 1}) => {
      'sucursal_id': 1,
      'items': [
        {
          'inventario_id': inventarioId,
          'producto_id': 101,
          'talla_id': 2,
          'color_id': 1,
          'nombre_producto': 'Camiseta básica',
          'cantidad': cantidad,
          'precio_unitario_centavos': 1999,
        },
      ],
    };

/// Catálogo local de una sola variante (inventario 1) con [stock] unidades.
List<Map<String, Object?>> _catalogoConStock(int stock) => [
      {
        'inventario_id': 1,
        'sucursal_id': 1,
        'producto_id': 101,
        'talla_id': 2,
        'color_id': 1,
        'nombre_producto': 'Camiseta básica',
        'precio_centavos': 1999,
        'cantidad_disponible': stock,
        'activo': 1,
      },
    ];

void main() {
  late AppDatabase appDb;
  late SyncQueueDao cola;
  late CatalogoLocalDao catalogo;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    appDb = AppDatabase.conBaseDeDatos(await AppDatabase.abrir(inMemoryDatabasePath));
    cola = SyncQueueDao(appDatabase: appDb);
    catalogo = CatalogoLocalDao(appDatabase: appDb);
  });

  tearDown(() => appDb.cerrar());

  Future<List<Map<String, Object?>>> filas(String tabla) async => (await appDb.database)!.query(tabla);

  Future<int> stockDe(int inventarioId) async =>
      (await (await appDb.database)!.query(Schema.tablaCatalogoLocal, columns: ['cantidad_disponible'], where: 'inventario_id = ?', whereArgs: [inventarioId]))
          .single['cantidad_disponible'] as int;

  // ---- backend falso: un Dio que responde sin salir a la red ---------------------------------------------------------
  final peticiones = <RequestOptions>[];
  setUp(peticiones.clear);

  Dio dioFalso(Object Function(RequestOptions o) responder) {
    final dio = Dio(BaseOptions(baseUrl: 'http://servidor-falso'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (o, handler) {
      peticiones.add(o);
      final r = responder(o);
      if (r is DioException) {
        handler.reject(r);
      } else {
        handler.resolve(r as Response<dynamic>);
      }
    }));
    return dio;
  }

  List<Map<String, dynamic>> operacionesDe(RequestOptions o) =>
      ((o.data as Map<String, dynamic>)['operaciones'] as List).cast<Map<String, dynamic>>();

  /// El servidor acepta todas las operaciones del lote (ids de servidor 500, 501...).
  Response<dynamic> aceptaTodo(RequestOptions o) {
    var id = 500;
    return Response(requestOptions: o, statusCode: 200, data: {
      'resultados': [for (final op in operacionesDe(o)) {'uuid': op['uuid'], 'status': 'ok', 'id_servidor': id++}],
    });
  }

  SyncService sincronizador(Dio dio, {bool Function()? conRed}) =>
      SyncService(colaDao: cola, hayRed: () async => conRed?.call() ?? true, dio: dio);

  // =====================================================================================================================
  group('CU9 · reserva offline con el CatalogoOfflineProvider', () {
    late CatalogoOfflineProvider provider;

    setUp(() async {
      provider = CatalogoOfflineProvider(catalogoDao: catalogo, colaDao: cola);
      await provider.cargarDatosMock();
    });

    test('a) y b) la reserva queda en SQLite como pendiente_sync y en sync_queue como RESERVA_CLIENTE', () async {
      final camiseta = provider.productos.firstWhere((p) => p.productoId == 101);
      final antes = camiseta.cantidadDisponible;

      expect(await provider.reservarProducto(camiseta, _clienteId), isTrue);

      // a) operaciones_locales
      final op = (await filas(Schema.tablaOperaciones)).single;
      expect(op['estado'], 'pendiente_sync');
      expect(op['tipo_operacion'], Schema.tipoReservaCliente);
      expect(op['cliente_id'], _clienteId);
      expect(op['cajero_id'], isNull);
      expect(op['id_servidor'], isNull, reason: 'todavía no llegó al backend');
      final items = await filas(Schema.tablaOperacionesItems);
      expect(items, hasLength(1));
      expect(items.single['producto_id'], 101);
      expect(items.single['cantidad'], 1);

      // b) sync_queue
      final q = (await filas(Schema.tablaSyncQueue)).single;
      expect(q['tipo_operacion'], 'RESERVA_CLIENTE');
      expect(q['estado'], 'pendiente');
      expect(q['intentos'], 0);
      expect(q['operacion_uuid'], op['uuid']);
      final payload = jsonDecode(q['payload_json'] as String) as Map<String, dynamic>;
      expect(payload['sucursal_id'], 1);
      expect((payload['items'] as List).single, containsPair('producto_id', 101));
      expect(payload['stock_local_descontado'], isTrue, reason: 'marca que esta reserva restó stock local');
      expect(await cola.obtenerOperacionesPendientes(), hasLength(1));
      expect(provider.pendientes, 1);

      // bloqueo optimista: el stock local ya bajó en 1
      expect(await stockDe(camiseta.inventarioId), antes - 1);
      expect(provider.productos.firstWhere((p) => p.productoId == 101).cantidadDisponible, antes - 1);
    });

    test('c) flujo completo: sin red no se envía; al volver la red va al backend y queda sincronizada', () async {
      final camiseta = provider.productos.firstWhere((p) => p.productoId == 101);
      final antes = camiseta.cantidadDisponible;
      expect(await provider.reservarProducto(camiseta, _clienteId), isTrue);
      final uuid = (await filas(Schema.tablaOperaciones)).single['uuid'] as String;

      var hayRed = false;
      final dio = dioFalso((o) => Response(requestOptions: o, statusCode: 200, data: {
            'resultados': [
              {'uuid': uuid, 'status': 'ok', 'id_servidor': 321},
            ],
          }));
      final sync = sincronizador(dio, conRed: () => hayRed);

      // --- sin conexión: no se envía nada y la reserva sigue pendiente
      final sinRed = await sync.sincronizarPendientes();
      expect(sinRed.sinRed, isTrue);
      expect(peticiones, isEmpty);
      expect((await filas(Schema.tablaOperaciones)).single['estado'], 'pendiente_sync');
      expect((await filas(Schema.tablaSyncQueue)).single['estado'], 'pendiente');

      // --- vuelve la red: se envía y se marca sincronizada
      hayRed = true;
      final r = await sync.sincronizarPendientes();

      expect(r.sincronizadas, 1);
      expect(r.rechazadas, 0);
      expect(r.fallidas, 0);
      expect(peticiones, hasLength(1));
      expect(peticiones.single.method, 'POST');
      expect(peticiones.single.path, '/sync/operaciones');
      final enviada = operacionesDe(peticiones.single).single;
      expect(enviada['uuid'], uuid);
      expect(enviada['tipo_operacion'], 'RESERVA_CLIENTE');
      expect(enviada['cliente_id'], _clienteId);
      expect(enviada['cajero_id'], isNull);
      expect((enviada['items'] as List).single, allOf(containsPair('producto_id', 101), containsPair('cantidad', 1)));

      final op = (await filas(Schema.tablaOperaciones)).single;
      expect(op['estado'], 'sincronizada');
      expect(op['id_servidor'], 321);
      expect((await filas(Schema.tablaSyncQueue)).single['estado'], 'sincronizado');
      expect(await cola.obtenerOperacionesPendientes(), isEmpty);

      // una reserva aceptada NO devuelve el stock: sigue reservado
      expect(await stockDe(camiseta.inventarioId), antes - 1);
    });

    test('un fallo de red al enviar deja la reserva pendiente_sync y el siguiente intento la sincroniza', () async {
      final camiseta = provider.productos.firstWhere((p) => p.productoId == 101);
      await provider.reservarProducto(camiseta, _clienteId);

      final caido = await sincronizador(dioFalso((o) => DioException(requestOptions: o, type: DioExceptionType.connectionError))).sincronizarPendientes();
      expect(caido.fallidas, 1);
      var op = (await filas(Schema.tablaOperaciones)).single;
      var q = (await filas(Schema.tablaSyncQueue)).single;
      expect(op['estado'], 'pendiente_sync');
      expect(q['estado'], 'pendiente');
      expect(q['intentos'], 1);
      expect(q['ultimo_error'], isNotNull);

      final ok = await sincronizador(dioFalso(aceptaTodo)).sincronizarPendientes();
      expect(ok.sincronizadas, 1);
      op = (await filas(Schema.tablaOperaciones)).single;
      q = (await filas(Schema.tablaSyncQueue)).single;
      expect(op['estado'], 'sincronizada');
      expect(op['id_servidor'], isNotNull);
      expect(q['estado'], 'sincronizado');
    });

    test('si el servidor rechaza la reserva (conflict) queda rechazada y el stock reservado vuelve', () async {
      final camiseta = provider.productos.firstWhere((p) => p.productoId == 101);
      final antes = camiseta.cantidadDisponible;
      await provider.reservarProducto(camiseta, _clienteId);
      expect(await stockDe(camiseta.inventarioId), antes - 1);

      final r = await sincronizador(dioFalso((o) => Response(requestOptions: o, statusCode: 200, data: {
            'resultados': [
              {'uuid': operacionesDe(o).single['uuid'], 'status': 'conflict', 'message': 'Stock insuficiente'},
            ],
          }))).sincronizarPendientes();

      expect(r.rechazadas, 1);
      expect((await filas(Schema.tablaOperaciones)).single['estado'], 'rechazada');
      final q = (await filas(Schema.tablaSyncQueue)).single;
      expect(q['estado'], 'rechazado');
      expect(q['ultimo_error'], 'Stock insuficiente');
      expect(await stockDe(camiseta.inventarioId), antes, reason: 'la reserva rechazada devuelve su unidad');
    });

    test('estrés: 5 reservas simultáneas de 5 productos distintos entran todas en la cola y se sincronizan', () async {
      final candidatos = provider.productos.where((p) => p.hayStock).take(5).toList();
      expect(candidatos, hasLength(5));
      final antes = {for (final p in candidatos) p.inventarioId: p.cantidadDisponible};

      final resultados = await Future.wait([for (final p in candidatos) provider.reservarProducto(p, _clienteId)]);

      expect(resultados, everyElement(isTrue));
      expect(await filas(Schema.tablaOperaciones), hasLength(5));
      expect(await filas(Schema.tablaSyncQueue), hasLength(5));
      expect((await filas(Schema.tablaSyncQueue)).map((q) => q['tipo_operacion']), everyElement('RESERVA_CLIENTE'));
      expect((await filas(Schema.tablaSyncQueue)).map((q) => q['estado']), everyElement('pendiente'));
      expect((await filas(Schema.tablaOperaciones)).map((o) => o['estado']), everyElement('pendiente_sync'));
      expect(provider.pendientes, 5);
      for (final p in candidatos) {
        final ahora = await stockDe(p.inventarioId);
        expect(ahora, antes[p.inventarioId]! - 1);
        expect(ahora, greaterThanOrEqualTo(0));
      }

      final r = await sincronizador(dioFalso(aceptaTodo)).sincronizarPendientes();
      expect(r.sincronizadas, 5);
      expect((await filas(Schema.tablaOperaciones)).map((o) => o['estado']), everyElement('sincronizada'));
      expect(await cola.obtenerOperacionesPendientes(), isEmpty);
    });
  });

  // =====================================================================================================================
  group('CU9 · estrés: 5 reservas simultáneas sobre la MISMA variante (DAO)', () {
    /// Lanza 5 reservas a la vez; cada resultado es 'guardada' o la excepción que lanzó.
    Future<List<Object>> cincoALaVez() => Future.wait([
          for (var i = 0; i < 5; i++)
            cola
                .guardarOperacionOffline(_reserva(), 'res-$i', Schema.tipoReservaCliente, _clienteId, descontarStockLocal: true)
                .then<Object>((_) => 'guardada')
                .catchError((Object e) => e),
        ]);

    test('con stock suficiente (8) entran las 5 y el stock queda en 3', () async {
      await catalogo.guardarLoteCatalogo(_catalogoConStock(8));

      final resultados = await cincoALaVez();

      expect(resultados, everyElement('guardada'));
      expect(await stockDe(1), 3);
      expect(await filas(Schema.tablaOperaciones), hasLength(5));
      expect(await filas(Schema.tablaOperacionesItems), hasLength(5));
      expect(await filas(Schema.tablaSyncQueue), hasLength(5));
      expect(await cola.obtenerOperacionesPendientes(), hasLength(5));
    });

    test('con stock insuficiente (3) entran solo 3, el stock nunca es negativo y no queda nada a medias', () async {
      await catalogo.guardarLoteCatalogo(_catalogoConStock(3));

      final resultados = await cincoALaVez();

      expect(resultados.where((r) => r == 'guardada'), hasLength(3));
      expect(resultados.whereType<StockLocalInsuficiente>(), hasLength(2), reason: 'las otras 2 se rechazan sin guardar nada');
      expect(await stockDe(1), 0);
      // las rechazadas hicieron rollback completo: ni cabecera, ni ítems, ni cola
      expect(await filas(Schema.tablaOperaciones), hasLength(3));
      expect(await filas(Schema.tablaOperacionesItems), hasLength(3));
      expect(await filas(Schema.tablaSyncQueue), hasLength(3));
      expect((await filas(Schema.tablaSyncQueue)).map((q) => q['tipo_operacion']), everyElement('RESERVA_CLIENTE'));

      // las 3 que sí entraron se sincronizan; el stock sigue en 0 (no se infla)
      final r = await sincronizador(dioFalso(aceptaTodo)).sincronizarPendientes();
      expect(r.sincronizadas, 3);
      expect((await filas(Schema.tablaOperaciones)).map((o) => o['estado']), everyElement('sincronizada'));
      expect(await stockDe(1), 0);
    });
  });
}
