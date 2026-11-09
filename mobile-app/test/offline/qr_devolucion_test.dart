import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlook_mobile/core/database/app_database.dart';
import 'package:smartlook_mobile/core/database/schema.dart';
import 'package:smartlook_mobile/features/offline/data/qr_devolucion_dao.dart';
import 'package:smartlook_mobile/features/offline/data/sync_queue_dao.dart';
import 'package:smartlook_mobile/features/offline/services/sync_service.dart';
import 'package:sqflite/sqflite.dart' show Sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Reembolso de un pedido cancelado: el QR bancario del cliente viaja como SUBIR_QR_DEVOLUCION en la cola de sincronización.
/// Sin conexión se guarda en SQLite; al volver la red se envía con `POST /sync/operaciones` (lista `qr_devoluciones`).
/// El backend es un Dio falso: no se toca ningún servidor.

final _png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, ...List.filled(64, 7)]);
final _jpg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, ...List.filled(64, 9)]);
final _webp = Uint8List.fromList([0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50, ...List.filled(32, 3)]);

const _reserva = 12;

void main() {
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

  Future<List<Map<String, Object?>>> colaQr() async =>
      (await appDb.database)!.query(Schema.tablaSyncQueue, where: 'tipo_operacion = ?', whereArgs: [Schema.tipoSubirQrDevolucion], orderBy: 'rowid');

  Map<String, dynamic> payload(Map<String, Object?> fila) => jsonDecode(fila['payload_json'] as String) as Map<String, dynamic>;

  // ---- backend falso: un Dio que responde sin salir a la red -------------------------------------------------------------
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

  Map<String, dynamic> cuerpo(RequestOptions o) => o.data as Map<String, dynamic>;
  Response<dynamic> http200(RequestOptions o, Object? datos) => Response(requestOptions: o, statusCode: 200, data: datos);
  DioException errorRed(RequestOptions o) => DioException(requestOptions: o, type: DioExceptionType.connectionError);
  DioException errorHttp(RequestOptions o, int codigo) =>
      DioException(requestOptions: o, type: DioExceptionType.badResponse, response: Response(requestOptions: o, statusCode: codigo));

  /// El servidor acepta todo lo que llega en el lote (ventas/reservas y QR).
  Response<dynamic> aceptaTodo(RequestOptions o) {
    var id = 100;
    final c = cuerpo(o);
    return http200(o, {
      'resultados': [
        for (final clave in const ['operaciones', 'qr_devoluciones'])
          for (final x in (c[clave] as List? ?? const [])) {'uuid': (x as Map)['uuid'], 'status': 'ok', 'id_servidor': id++},
      ],
    });
  }

  SyncService sync(Dio dio, {bool Function()? conRed}) => SyncService(colaDao: cola, qrDao: qr, hayRed: () async => conRed?.call() ?? true, dio: dio);

  // =====================================================================================================================
  group('QrDevolucionDao: el QR se guarda en la cola de sincronización', () {
    test('encolar deja una entrada SUBIR_QR_DEVOLUCION pendiente, con la imagen en base64 y sin ninguna operación asociada', () async {
      final colaId = await qr.encolar(reservaId: _reserva, imagen: _png, nombreArchivo: 'mi_qr.png');

      final fila = (await colaQr()).single;
      expect(fila['id'], colaId);
      expect(fila['tipo_operacion'], 'SUBIR_QR_DEVOLUCION');
      expect(fila['estado'], 'pendiente');
      expect(fila['intentos'], 0);
      expect((fila['operacion_uuid'], fila['turno_uuid'], fila['devolucion_id'], fila['movimiento_puntos_id']), (null, null, null, null));
      final p = payload(fila);
      expect(p['reserva_id'], _reserva);
      expect(p.containsKey('venta_id'), isFalse);
      expect(p['nombre_archivo'], 'mi_qr.png');
      expect(base64Decode(p['imagen_base64'] as String), _png);
      expect(await cola.obtenerOperacionesPendientes(), hasLength(1)); // cuenta como pendiente de sincronizar
      expect((await qr.estados())['reserva:$_reserva']?.estado, EstadoQrLocal.enCola);
    });

    test('una venta cancelada también admite su QR', () async {
      await qr.encolar(ventaId: 33, imagen: _jpg);

      final p = payload((await colaQr()).single);
      expect(p['venta_id'], 33);
      expect(p.containsKey('reserva_id'), isFalse);
      expect((await qr.estados()).keys, ['venta:33']);
    });

    test('valida la imagen por su CONTENIDO (PNG, JPG o WEBP), no por la extensión, y no guarda nada si no sirve', () async {
      for (final ok in [_png, _jpg, _webp]) {
        await qr.encolar(reservaId: 1, imagen: ok);
      }
      expect(await colaQr(), hasLength(1)); // el mismo pedido: cada uno reemplazó al anterior

      final invalidos = <String, List<int>>{
        'vacía': const [],
        'texto con extensión .png': utf8.encode('esto no es una imagen'),
        'demasiado grande': [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, ...List.filled(QrDevolucionDao.maxBytes, 0)],
      };
      for (final MapEntry(key: caso, value: bytes) in invalidos.entries) {
        await expectLater(qr.encolar(reservaId: 2, imagen: bytes, nombreArchivo: 'qr.png'), throwsA(isA<QrInvalido>()), reason: caso);
      }
      expect((await colaQr()).where((f) => payload(f)['reserva_id'] == 2), isEmpty);
    });

    test('hay que indicar la reserva o la venta, pero no las dos', () async {
      expect(() => qr.encolar(imagen: _png), throwsArgumentError);
      expect(() => qr.encolar(reservaId: 1, ventaId: 2, imagen: _png), throwsArgumentError);
      expect(await colaQr(), isEmpty);
    });

    test('un QR nuevo reemplaza al anterior del MISMO pedido (que aún no se envió); los demás pedidos no se tocan', () async {
      await qr.encolar(reservaId: 1, imagen: _png);
      await qr.encolar(reservaId: 2, imagen: _png);
      await qr.encolar(ventaId: 1, imagen: _png);

      await qr.encolar(reservaId: 1, imagen: _jpg, nombreArchivo: 'nuevo.jpg');

      final filas = await colaQr();
      expect(filas, hasLength(3));
      final reserva1 = filas.map(payload).singleWhere((p) => p['reserva_id'] == 1);
      expect(reserva1['nombre_archivo'], 'nuevo.jpg');
      expect(base64Decode(reserva1['imagen_base64'] as String), _jpg);
      expect(filas.map(payload).where((p) => p['reserva_id'] == 2), hasLength(1));
      expect(filas.map(payload).where((p) => p['venta_id'] == 1), hasLength(1));
    });

    test('sincronizado: se descarta la imagen y deja de aparecer; un rechazo conserva el motivo', () async {
      final a = await qr.encolar(reservaId: 1, imagen: _png);
      final b = await qr.encolar(reservaId: 2, imagen: _png);

      await qr.marcarSincronizado(a);
      await qr.marcarRechazado(b, 'La imagen no es válida');

      final filas = {for (final f in await colaQr()) f['id']: f};
      expect(filas[a]!['estado'], 'sincronizado');
      expect(payload(filas[a]!).containsKey('imagen_base64'), isFalse, reason: 'la imagen ya no hace falta');
      expect(filas[b]!['estado'], 'rechazado');
      expect(filas[b]!['ultimo_error'], 'La imagen no es válida');
      final estados = await qr.estados();
      expect(estados.containsKey('reserva:1'), isFalse);
      expect(estados['reserva:2']?.estado, EstadoQrLocal.rechazado);
      expect(estados['reserva:2']?.motivo, 'La imagen no es válida');
      await expectLater(qr.marcarSincronizado(a), throwsStateError); // ya cerrada: no se pisa

      // después de un rechazo el cliente puede adjuntar otro: reemplaza al rechazado
      await qr.encolar(reservaId: 2, imagen: _jpg);
      expect((await qr.estados())['reserva:2']?.estado, EstadoQrLocal.enCola);
    });
  });

  // =====================================================================================================================
  group('SyncService: envía los QR pendientes con POST /sync/operaciones', () {
    test('SIN red no se envía nada: el QR queda guardado en el celular', () async {
      await qr.encolar(reservaId: _reserva, imagen: _png);

      final r = await sync(dioFalso(aceptaTodo), conRed: () => false).sincronizarPendientes();

      expect(r.sinRed, isTrue);
      expect(peticiones, isEmpty);
      final fila = (await colaQr()).single;
      expect(fila['estado'], 'pendiente');
      expect(fila['intentos'], 0);
      expect(payload(fila).containsKey('imagen_base64'), isTrue, reason: 'la imagen sigue guardada hasta que llegue al servidor');
    });

    test('CON red se envía: el lote lleva el uuid de la cola, el pedido y la imagen; queda sincronizado y la imagen se descarta', () async {
      final colaId = await qr.encolar(reservaId: _reserva, imagen: _png, nombreArchivo: 'mi_qr.png');
      final servidor = dioFalso((o) => http200(o, {
            'resultados': [
              {'uuid': colaId, 'status': 'ok', 'id_servidor': 9, 'entidad': 'reembolso'},
            ],
          }));

      final r = await sync(servidor).sincronizarPendientes();

      expect((r.sincronizadas, r.rechazadas, r.fallidas), (1, 0, 0));
      expect(peticiones, hasLength(1));
      expect(peticiones.single.method, 'POST');
      expect(peticiones.single.path, '/sync/operaciones');
      final lote = cuerpo(peticiones.single);
      expect(lote.containsKey('operaciones'), isFalse);
      final enviado = (lote['qr_devoluciones'] as List).single as Map<String, dynamic>;
      expect(enviado['uuid'], colaId);
      expect(enviado['reserva_id'], _reserva);
      expect(enviado['nombre_archivo'], 'mi_qr.png');
      expect(base64Decode(enviado['imagen_base64'] as String), _png);

      final fila = (await colaQr()).single;
      expect(fila['estado'], 'sincronizado');
      expect(payload(fila).containsKey('imagen_base64'), isFalse);
      expect(await qr.estados(), isEmpty);
      expect(await cola.obtenerOperacionesPendientes(), isEmpty);
    });

    test('el cliente reserva SIN red, vuelve la red y al sincronizar sube el QR: el flujo completo offline → online', () async {
      final colaId = await qr.encolar(reservaId: _reserva, imagen: _png);
      var hayRed = false;
      final servicio = sync(dioFalso(aceptaTodo), conRed: () => hayRed);

      expect((await servicio.sincronizarPendientes()).sinRed, isTrue);
      expect((await colaQr()).single['estado'], 'pendiente');

      hayRed = true; // vuelve la conexión
      final r = await servicio.sincronizarPendientes();

      expect(r.sincronizadas, 1);
      expect((await colaQr()).single, containsPair('estado', 'sincronizado'));
      expect(((cuerpo(peticiones.single)['qr_devoluciones'] as List).single as Map)['uuid'], colaId);
    });

    test('si el servidor lo rechaza (conflict) queda rechazado con el motivo y no se reintenta', () async {
      final colaId = await qr.encolar(reservaId: _reserva, imagen: _png);
      final servidor = dioFalso((o) => http200(o, {
            'resultados': [
              {'uuid': colaId, 'status': 'conflict', 'message': 'Este pedido ya fue reembolsado'},
            ],
          }));

      final r = await sync(servidor).sincronizarPendientes();

      expect((r.sincronizadas, r.rechazadas), (0, 1));
      final fila = (await colaQr()).single;
      expect((fila['estado'], fila['ultimo_error']), ('rechazado', 'Este pedido ya fue reembolsado'));
      expect((await qr.estados())['reserva:$_reserva']?.estado, EstadoQrLocal.rechazado);
      await sync(servidor).sincronizarPendientes();
      expect(peticiones, hasLength(1), reason: 'un rechazado ya no se vuelve a enviar');
    });

    test('un corte de red al enviar deja el QR pendiente y el reintento usa el MISMO uuid (idempotencia)', () async {
      final colaId = await qr.encolar(reservaId: _reserva, imagen: _png);

      final caido = await sync(dioFalso(errorRed)).sincronizarPendientes();
      expect(caido.fallidas, 1);
      var fila = (await colaQr()).single;
      expect((fila['estado'], fila['intentos']), ('pendiente', 1));
      expect(fila['ultimo_error'], isNotNull);

      final ok = await sync(dioFalso(aceptaTodo)).sincronizarPendientes();

      expect(ok.sincronizadas, 1);
      fila = (await colaQr()).single;
      expect((fila['estado'], fila['intentos']), ('sincronizado', 2));
      final uuids = peticiones.map((p) => ((cuerpo(p)['qr_devoluciones'] as List).single as Map)['uuid']).toSet();
      expect(uuids, {colaId});
    });

    test('error 500 y timeout: sigue pendiente; 401: se detiene, avisa de sesión expirada y no pierde nada', () async {
      await qr.encolar(reservaId: _reserva, imagen: _png);

      expect((await sync(dioFalso((o) => errorHttp(o, 500))).sincronizarPendientes()).fallidas, 1);
      expect((await sync(dioFalso((o) => DioException(requestOptions: o, type: DioExceptionType.receiveTimeout))).sincronizarPendientes()).fallidas, 1);
      final r = await sync(dioFalso((o) => errorHttp(o, 401))).sincronizarPendientes();

      expect(r.sesionExpirada, isTrue);
      final fila = (await colaQr()).single;
      expect(fila['estado'], 'pendiente');
      expect(payload(fila).containsKey('imagen_base64'), isTrue);
    });

    test('"pendiente" del servidor: el QR espera sin contarse como fallo', () async {
      final colaId = await qr.encolar(reservaId: _reserva, imagen: _png);
      final servidor = dioFalso((o) => http200(o, {
            'resultados': [
              {'uuid': colaId, 'status': 'pendiente', 'message': 'Espera la venta'},
            ],
          }));

      final r = await sync(servidor).sincronizarPendientes();

      expect((r.enEspera, r.fallidas), (1, 0));
      expect((await colaQr()).single['estado'], 'pendiente');
    });

    test('una respuesta global {"status": "ok"} también sincroniza el QR', () async {
      await qr.encolar(reservaId: _reserva, imagen: _png);

      final r = await sync(dioFalso((o) => http200(o, {'status': 'ok'}))).sincronizarPendientes();

      expect(r.sincronizadas, 1);
      expect((await colaQr()).single['estado'], 'sincronizado');
    });

    test('junto con una reserva offline: la reserva va en `operaciones` y el QR en `qr_devoluciones`, y ambos se sincronizan', () async {
      await cola.guardarOperacionOffline(
        {
          'sucursal_id': 1,
          'items': [
            {'producto_id': 101, 'talla_id': 2, 'color_id': 1, 'nombre_producto': 'Camiseta', 'cantidad': 1, 'precio_unitario_centavos': 1999},
          ],
        },
        'res-1',
        Schema.tipoReservaCliente,
        55,
      );
      final colaId = await qr.encolar(reservaId: _reserva, imagen: _png);

      final r = await sync(dioFalso(aceptaTodo)).sincronizarPendientes();

      expect(r.sincronizadas, 2);
      expect(peticiones, hasLength(2));
      final lotes = peticiones.map(cuerpo).toList();
      final delasOperaciones = lotes.singleWhere((l) => l.containsKey('operaciones'));
      expect((delasOperaciones['operaciones'] as List).single, containsPair('tipo_operacion', 'RESERVA_CLIENTE'));
      expect(delasOperaciones.containsKey('qr_devoluciones'), isFalse);
      final delQr = lotes.singleWhere((l) => l.containsKey('qr_devoluciones'));
      expect(((delQr['qr_devoluciones'] as List).single as Map)['uuid'], colaId);
      expect((await (await appDb.database)!.query(Schema.tablaOperaciones)).single['estado'], 'sincronizada');
      expect((await colaQr()).single['estado'], 'sincronizado');
    });
  });

  // =====================================================================================================================
  group('migración v6 → v7: sync_queue admite SUBIR_QR_DEVOLUCION', () {
    late String ruta;

    setUp(() => ruta = '${Directory.systemTemp.path}${Platform.pathSeparator}smartlook_mig7_${DateTime.now().microsecondsSinceEpoch}.db');

    tearDown(() async {
      for (final sufijo in ['', '-journal', '-wal', '-shm']) {
        final f = File('$ruta$sufijo');
        if (await f.exists()) await f.delete();
      }
    });

    /// La `sync_queue` tal como era en v6 (sin el tipo SUBIR_QR_DEVOLUCION).
    const syncQueueV6 = '''
CREATE TABLE sync_queue (
  id TEXT PRIMARY KEY,
  tipo_operacion TEXT NOT NULL
    CHECK (tipo_operacion IN ('VENTA_CONTADO', 'RESERVA_CLIENTE', 'CIERRE_CAJA', 'DEVOLUCION',
                              'PUNTOS_OTORGADOS', 'PUNTOS_RESTADOS')),
  operacion_uuid TEXT REFERENCES operaciones_locales(uuid) ON DELETE RESTRICT,
  turno_uuid TEXT REFERENCES turnos_caja(id) ON DELETE RESTRICT,
  devolucion_id TEXT REFERENCES devoluciones_locales(id) ON DELETE RESTRICT,
  movimiento_puntos_id TEXT REFERENCES movimientos_puntos(id) ON DELETE RESTRICT,
  payload_json TEXT NOT NULL,
  estado TEXT NOT NULL DEFAULT 'pendiente'
    CHECK (estado IN ('pendiente', 'en_proceso', 'sincronizado', 'error', 'rechazado', 'en_conflicto')),
  intentos INTEGER NOT NULL DEFAULT 0 CHECK (intentos >= 0),
  ultimo_error TEXT,
  fecha_ultimo_intento TEXT,
  fecha_creacion TEXT NOT NULL,
  CHECK (tipo_operacion <> 'CIERRE_CAJA' OR (turno_uuid IS NOT NULL AND operacion_uuid IS NULL)),
  CHECK (tipo_operacion <> 'DEVOLUCION' OR
         (devolucion_id IS NOT NULL AND operacion_uuid IS NULL AND turno_uuid IS NULL)),
  CHECK (tipo_operacion NOT IN ('PUNTOS_OTORGADOS', 'PUNTOS_RESTADOS') OR
         (movimiento_puntos_id IS NOT NULL AND operacion_uuid IS NULL AND turno_uuid IS NULL
          AND devolucion_id IS NULL))
)''';

    Map<String, Object?> filaQr(String id) => {
          'id': id,
          'tipo_operacion': 'SUBIR_QR_DEVOLUCION',
          'payload_json': jsonEncode({'reserva_id': 1, 'imagen_base64': base64Encode(_png)}),
          'estado': 'pendiente',
          'fecha_creacion': '2026-11-09T10:00:00Z',
        };

    test('lo que ya estaba en la cola se conserva y la cola empieza a aceptar los QR (con sus reglas)', () async {
      final v6 = await openDatabase(
        ruta,
        version: 6,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) async {
          for (final s in Schema.ddl) {
            await db.execute(s.contains('CREATE TABLE sync_queue (') ? syncQueueV6 : s);
          }
        },
      );
      await v6.insert('operaciones_locales', {
        'uuid': 'v1', 'tipo_operacion': 'VENTA_CONTADO', 'sucursal_id': 1, 'cajero_id': 7, 'total_centavos': 1999,
        'fecha': '2026-11-01T10:00:00Z', 'estado': 'pendiente_sync',
      });
      await v6.insert('sync_queue', {
        'id': 'q1', 'tipo_operacion': 'VENTA_CONTADO', 'operacion_uuid': 'v1', 'payload_json': '{"sucursal_id":1,"items":[]}',
        'estado': 'pendiente', 'intentos': 2, 'ultimo_error': 'sin red', 'fecha_creacion': '2026-11-01T10:00:00Z',
      });
      await expectLater(v6.insert('sync_queue', filaQr('x0')), throwsA(anything), reason: 'en v6 el tipo todavía no existe'); // la migración hace falta
      await v6.close();

      final db = await AppDatabase.abrir(ruta); // → onUpgrade(6, versión actual)
      final nuevo = AppDatabase.conBaseDeDatos(db);
      addTearDown(nuevo.cerrar);

      expect(Sqflite.firstIntValue(await db.rawQuery('PRAGMA user_version')), Schema.version); // sigue hasta la última versión
      expect(Sqflite.firstIntValue(await db.rawQuery('PRAGMA foreign_keys')), 1);
      final q1 = (await db.query('sync_queue', where: 'id = ?', whereArgs: ['q1'])).single;
      expect((q1['operacion_uuid'], q1['estado'], q1['intentos'], q1['ultimo_error']), ('v1', 'pendiente', 2, 'sin red'));
      expect(await db.query('operaciones_locales'), hasLength(1)); // la tabla padre no se tocó

      await db.insert('sync_queue', filaQr('x1')); // ahora sí
      await QrDevolucionDao(appDatabase: nuevo).encolar(reservaId: 5, imagen: _png);
      expect(await db.query('sync_queue', where: "tipo_operacion = 'SUBIR_QR_DEVOLUCION'"), hasLength(2));
      // un QR no cuelga de ninguna operación: el CHECK nuevo lo vigila
      await expectLater(db.insert('sync_queue', {...filaQr('x2'), 'operacion_uuid': 'v1'}), throwsA(anything));
      await expectLater(db.insert('sync_queue', {...filaQr('x3'), 'tipo_operacion': 'OTRO'}), throwsA(anything));
    });
  });
}
