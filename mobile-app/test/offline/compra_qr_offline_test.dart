import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smartlook_mobile/core/database/app_database.dart';
import 'package:smartlook_mobile/core/database/schema.dart';
import 'package:smartlook_mobile/core/models/usuario.dart';
import 'package:smartlook_mobile/features/auth/providers/auth_provider.dart';
import 'package:smartlook_mobile/features/encargado/mi_qr/models/sucursal_qr.dart';
import 'package:smartlook_mobile/features/offline/data/catalogo_local_dao.dart';
import 'package:smartlook_mobile/features/offline/data/qr_sucursal_cache_dao.dart';
import 'package:smartlook_mobile/features/offline/data/sync_queue_dao.dart';
import 'package:smartlook_mobile/features/offline/models/catalogo_item.dart';
import 'package:smartlook_mobile/features/offline/providers/catalogo_offline_provider.dart';
import 'package:smartlook_mobile/features/offline/providers/conectividad_provider.dart';
import 'package:smartlook_mobile/features/offline/providers/suscripciones_provider.dart';
import 'package:smartlook_mobile/features/offline/screens/catalogo_offline_screen.dart';
import 'package:smartlook_mobile/features/offline/services/catalogo_sync_service.dart';
import 'package:smartlook_mobile/features/offline/services/qr_sucursal_cache.dart';
import 'package:smartlook_mobile/features/offline/services/sync_service.dart';
import 'package:smartlook_mobile/features/offline/widgets/compra_qr_sheet.dart';
import 'package:smartlook_mobile/features/reservas/widgets/selector_qr.dart';
import 'package:sqflite/sqflite.dart' show Sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Compra offline del cliente con pago QR y comprobante (VENTA_CLIENTE_QR):
/// sin red → se ve el QR de la sucursal (guardado en el celular) → se sube el comprobante → la compra queda en la cola de
/// sincronización con el comprobante en base64 y el stock local baja → al volver la red se envía.
/// El backend es un Dio falso: no se toca ningún servidor.

// PNG real de 1x1 píxel (los widgets lo decodifican de verdad).
final _png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');
final _jpg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, ...List.filled(64, 9)]);

const _cliente = 55;

CatalogoItem _item({int id = 1, int stock = 5, int sucursal = 1}) => CatalogoItem(
      inventarioId: id,
      sucursalId: sucursal,
      productoId: 100 + id,
      tallaId: 2,
      colorId: 1,
      nombre: 'Camisa Oxford',
      nombreTalla: 'M',
      nombreColor: 'Negro',
      precioCentavos: 10000,
      cantidadDisponible: stock,
      activo: true,
    );

Map<String, Object?> _fila({int id = 1, int stock = 5, int sucursal = 1}) => {
      'inventario_id': id,
      'sucursal_id': sucursal,
      'producto_id': 100 + id,
      'talla_id': 2,
      'color_id': 1,
      'nombre_producto': 'Camisa Oxford',
      'nombre_talla': 'M',
      'nombre_color': 'Negro',
      'precio_centavos': 10000,
      'cantidad_disponible': stock,
      'activo': 1,
    };

void main() {
  late AppDatabase appDb;
  late SyncQueueDao cola;
  late CatalogoLocalDao catalogo;
  late QrSucursalCacheDao cacheDao;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    appDb = AppDatabase.conBaseDeDatos(await AppDatabase.abrir(inMemoryDatabasePath));
    cola = SyncQueueDao(appDatabase: appDb);
    catalogo = CatalogoLocalDao(appDatabase: appDb);
    cacheDao = QrSucursalCacheDao(appDatabase: appDb);
  });

  tearDown(() => appDb.cerrar());

  Future<List<Map<String, Object?>>> filas(String tabla) async => (await appDb.database)!.query(tabla);
  Future<int> stock(int inventarioId) async =>
      (await (await appDb.database)!.query(Schema.tablaCatalogoLocal, columns: ['cantidad_disponible'], where: 'inventario_id = ?', whereArgs: [inventarioId]))
          .single['cantidad_disponible'] as int;
  Map<String, dynamic> payload(Map<String, Object?> fila) => jsonDecode(fila['payload_json'] as String) as Map<String, dynamic>;

  // ---- backend falso -------------------------------------------------------------------------------------------------
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

  Response<dynamic> resultados(RequestOptions o, String status, {String? mensaje}) => Response(requestOptions: o, statusCode: 200, data: {
        'resultados': [
          for (final op in ((o.data as Map)['operaciones'] as List))
            {'uuid': (op as Map)['uuid'], 'status': status, if (status == 'ok') 'id_servidor': 40, 'message': ?mensaje},
        ],
      });

  SyncService sync(Dio dio, {bool Function()? conRed}) => SyncService(colaDao: cola, hayRed: () async => conRed?.call() ?? true, dio: dio);

  // =====================================================================================================================
  group('la compra offline se guarda en SQLite y en la cola con el comprobante en base64', () {
    late CatalogoOfflineProvider provider;

    setUp(() async {
      await catalogo.guardarLoteCatalogo([_fila(id: 1, stock: 5), _fila(id: 2, stock: 1, sucursal: 2)]);
      provider = CatalogoOfflineProvider(catalogoDao: catalogo, colaDao: cola);
      await provider.cargar();
    });

    test('comprarConQr guarda una VENTA_CLIENTE_QR pendiente_sync y el comprobante viaja en base64 dentro de sync_queue', () async {
      final camisa = provider.productos.firstWhere((p) => p.inventarioId == 1);

      expect(await provider.comprarConQr(camisa, _cliente, cantidad: 2, comprobante: _png, nombreComprobante: 'transferencia.png'), isTrue);

      final op = (await filas(Schema.tablaOperaciones)).single;
      expect(op['tipo_operacion'], 'VENTA_CLIENTE_QR');
      expect((op['estado'], op['cliente_id'], op['cajero_id'], op['id_servidor']), ('pendiente_sync', _cliente, null, null));
      expect(op['total_centavos'], 20000);
      final items = await filas(Schema.tablaOperacionesItems);
      expect((items.single['producto_id'], items.single['cantidad']), (101, 2));

      final q = (await filas(Schema.tablaSyncQueue)).single;
      expect((q['tipo_operacion'], q['estado'], q['operacion_uuid']), ('VENTA_CLIENTE_QR', 'pendiente', op['uuid']));
      final p = payload(q);
      expect(base64Decode(p['comprobante_base64'] as String), _png, reason: 'el comprobante viaja en base64 por la cola');
      expect(p['comprobante_nombre'], 'transferencia.png');
      expect(p['stock_local_descontado'], isTrue);
      expect(provider.pendientes, 1);
      expect(provider.ultimoMensaje, contains('Compra guardada'));
    });

    test('el stock local baja con la cantidad comprada (descuento optimista) y sin comprobante válido no se guarda nada', () async {
      final camisa = provider.productos.firstWhere((p) => p.inventarioId == 1);

      expect(await provider.comprarConQr(camisa, _cliente, cantidad: 2, comprobante: _png), isTrue);
      expect(await stock(1), 3);
      expect(provider.productos.firstWhere((p) => p.inventarioId == 1).cantidadDisponible, 3);

      expect(await provider.comprarConQr(provider.productos.first, _cliente, cantidad: 1, comprobante: utf8.encode('no es una imagen')), isFalse);
      expect(provider.ultimoMensaje, contains('El comprobante no sirve'));
      expect(await provider.comprarConQr(provider.productos.first, _cliente, cantidad: 1, comprobante: const []), isFalse);
      expect(await stock(1), 3);
      expect(await filas(Schema.tablaSyncQueue), hasLength(1));
    });

    test('no se puede comprar más de lo que hay: el stock local nunca queda negativo', () async {
      final ultima = provider.productos.firstWhere((p) => p.inventarioId == 2); // 1 unidad

      expect(await provider.comprarConQr(ultima, _cliente, cantidad: 2, comprobante: _png), isFalse);
      expect(provider.ultimoMensaje, contains('Solo quedan 1'));
      expect(await provider.comprarConQr(ultima, _cliente, cantidad: 1, comprobante: _png), isTrue);
      expect(await stock(2), 0);
      expect(await provider.comprarConQr(provider.productos.firstWhere((p) => p.inventarioId == 2), _cliente, cantidad: 1, comprobante: _png), isFalse);
      expect(await stock(2), 0);
      expect(await filas(Schema.tablaOperaciones), hasLength(1));
    });

    test('la cola exige cliente, ningún cajero y comprobante en una VENTA_CLIENTE_QR', () async {
      Map<String, dynamic> json({Object? comprobante = 'abc', int? cajero}) => {
            'sucursal_id': 1,
            'cajero_id': cajero,
            'items': [
              {'inventario_id': 1, 'producto_id': 101, 'nombre_producto': 'x', 'cantidad': 1, 'precio_unitario_centavos': 100},
            ],
            'comprobante_base64': comprobante,
          };
      Future<String> guardar(Map<String, dynamic> j, int? cliente) => cola.guardarOperacionOffline(j, 'u', Schema.tipoVentaClienteQr, cliente, descontarStockLocal: true);

      await expectLater(guardar(json(), null), throwsArgumentError);
      await expectLater(guardar(json(cajero: 7), _cliente), throwsArgumentError);
      await expectLater(guardar(json(comprobante: null), _cliente), throwsArgumentError);
      await expectLater(guardar(json(comprobante: ''), _cliente), throwsArgumentError);
      expect(await filas(Schema.tablaOperaciones), isEmpty);
      expect(await stock(1), 5);
    });

    test('el comprobante viaja en base64 en el lote: sin red no se envía; al volver la red va al servidor y la compra queda sincronizada', () async {
      final camisa = provider.productos.firstWhere((p) => p.inventarioId == 1);
      await provider.comprarConQr(camisa, _cliente, cantidad: 2, comprobante: _png, nombreComprobante: 'transferencia.png');
      final uuid = (await filas(Schema.tablaOperaciones)).single['uuid'] as String;
      var hayRed = false;
      final servicio = sync(dioFalso((o) => resultados(o, 'ok')), conRed: () => hayRed);

      expect((await servicio.sincronizarPendientes()).sinRed, isTrue);
      expect(peticiones, isEmpty);
      expect((await filas(Schema.tablaOperaciones)).single['estado'], 'pendiente_sync');

      hayRed = true;
      final r = await servicio.sincronizarPendientes();

      expect((r.sincronizadas, r.rechazadas, r.fallidas), (1, 0, 0));
      expect(peticiones.single.path, '/sync/operaciones');
      final enviada = (((peticiones.single.data as Map)['operaciones']) as List).single as Map;
      expect(enviada['uuid'], uuid);
      expect(enviada['tipo_operacion'], 'VENTA_CLIENTE_QR');
      expect(enviada['cliente_id'], _cliente);
      expect(enviada['cajero_id'], isNull);
      expect(enviada['comprobante_nombre'], 'transferencia.png');
      expect(base64Decode(enviada['comprobante_base64'] as String), _png);
      expect((enviada['items'] as List).single, allOf(containsPair('producto_id', 101), containsPair('cantidad', 2)));
      expect(enviada['total_centavos'], 20000);

      final op = (await filas(Schema.tablaOperaciones)).single;
      expect((op['estado'], op['id_servidor']), ('sincronizada', 40));
      final q = (await filas(Schema.tablaSyncQueue)).single;
      expect(q['estado'], 'sincronizado');
      expect(payload(q).containsKey('comprobante_base64'), isFalse, reason: 'el comprobante ya está en el servidor: no se guarda dos veces');
      expect(await stock(1), 3, reason: 'una compra aceptada sigue con su stock descontado');
    });

    test('si el servidor la rechaza queda rechazada, el stock vuelve y el comprobante se descarta', () async {
      final camisa = provider.productos.firstWhere((p) => p.inventarioId == 1);
      await provider.comprarConQr(camisa, _cliente, cantidad: 2, comprobante: _png);
      expect(await stock(1), 3);

      final r = await sync(dioFalso((o) => resultados(o, 'conflict', mensaje: 'El comprobante de pago no es válido'))).sincronizarPendientes();

      expect(r.rechazadas, 1);
      expect((await filas(Schema.tablaOperaciones)).single['estado'], 'rechazada');
      final q = (await filas(Schema.tablaSyncQueue)).single;
      expect((q['estado'], q['ultimo_error']), ('rechazado', 'El comprobante de pago no es válido'));
      expect(payload(q).containsKey('comprobante_base64'), isFalse);
      expect(await stock(1), 5, reason: 'lo que la compra había descontado vuelve al catálogo local');
    });

    test('un corte de red al enviar deja la compra pendiente (con su comprobante) para reintentar', () async {
      final camisa = provider.productos.firstWhere((p) => p.inventarioId == 1);
      await provider.comprarConQr(camisa, _cliente, cantidad: 1, comprobante: _png);

      final r = await sync(dioFalso((o) => DioException(requestOptions: o, type: DioExceptionType.connectionError))).sincronizarPendientes();

      expect(r.fallidas, 1);
      final q = (await filas(Schema.tablaSyncQueue)).single;
      expect((q['estado'], q['intentos']), ('pendiente', 1));
      expect(payload(q).containsKey('comprobante_base64'), isTrue);
      expect((await filas(Schema.tablaOperaciones)).single['estado'], 'pendiente_sync');
    });

    test('la reserva sigue igual: una RESERVA_CLIENTE no lleva comprobante y viaja en el mismo lote que la compra', () async {
      final camisa = provider.productos.firstWhere((p) => p.inventarioId == 1);
      expect(await provider.reservarProducto(camisa, _cliente), isTrue);
      final reservada = provider.productos.firstWhere((p) => p.inventarioId == 1);
      expect(await provider.comprarConQr(reservada, _cliente, cantidad: 1, comprobante: _png), isTrue);
      expect(await stock(1), 3);

      final r = await sync(dioFalso((o) => resultados(o, 'ok'))).sincronizarPendientes();

      expect(r.sincronizadas, 2);
      final ops = (((peticiones.single.data as Map)['operaciones']) as List).cast<Map>();
      final reserva = ops.singleWhere((o) => o['tipo_operacion'] == 'RESERVA_CLIENTE');
      final compra = ops.singleWhere((o) => o['tipo_operacion'] == 'VENTA_CLIENTE_QR');
      expect(reserva.containsKey('comprobante_base64'), isFalse);
      expect(compra['comprobante_base64'], isNotEmpty);
      expect((await filas(Schema.tablaOperaciones)).map((o) => o['estado']), everyElement('sincronizada'));
    });
  });

  // =====================================================================================================================
  group('el QR de la sucursal se guarda en el celular para mostrarlo sin conexión', () {
    SucursalQR qr(int sucursal, {bool activo = true, String url = '/uploads/qr/s.png'}) => SucursalQR(
          id: sucursal, sucursalId: sucursal, imagenPath: 'qr/s.png', imagenUrl: url, activo: activo, creadoEn: DateTime(2026, 1, 1),
        );

    test('el DAO guarda, reemplaza y borra la imagen de una sucursal', () async {
      expect(await cacheDao.obtener(1), isNull);

      await cacheDao.guardar(1, _png, url: '/uploads/qr/a.png');
      expect(await cacheDao.obtener(1), _png);
      final fila = (await filas(Schema.tablaQrSucursalCache)).single;
      expect(fila['imagen_url'], '/uploads/qr/a.png', reason: 'la tabla local guarda la ruta del QR además de la imagen');
      expect(fila['actualizado_en'], isNotNull);
      await cacheDao.guardar(1, _jpg);
      expect(await cacheDao.obtener(1), _jpg);
      expect(await filas(Schema.tablaQrSucursalCache), hasLength(1));
      expect(await cacheDao.obtener(2), isNull);
      await cacheDao.eliminar(1);
      expect(await cacheDao.obtener(1), isNull);
    });

    test('actualizar descarga y guarda el QR de cada sucursal; una sucursal sin QR activo borra el viejo; un fallo no detiene a las demás', () async {
      await cacheDao.guardar(2, _jpg); // un QR viejo de una sucursal que ya no tiene
      final descargadas = <String>[];
      final cache = QrSucursalCache(
        dao: cacheDao,
        consultar: (id) async {
          if (id == 3) throw Exception('sin red');
          return id == 2 ? null : qr(id);
        },
        descargar: (url) async {
          descargadas.add(url);
          return _png;
        },
      );

      final guardadas = await cache.actualizar([1, 2, 3, 1, 4]);

      expect(guardadas, 2); // 1 y 4 (2 sin QR, 3 falló)
      expect(await cache.obtener(1), _png);
      expect(await cache.obtener(4), _png);
      expect(await cache.obtener(2), isNull, reason: 'la sucursal 2 ya no tiene QR activo');
      expect(await cache.obtener(3), isNull);
      expect(descargadas, hasLength(2));
      expect(descargadas.first, endsWith('/uploads/qr/s.png'));
    });

    DioException respuesta(int codigo) => DioException(
          requestOptions: RequestOptions(path: '/uploads/qr/s.png'),
          type: DioExceptionType.badResponse,
          response: Response(requestOptions: RequestOptions(path: '/uploads/qr/s.png'), statusCode: codigo),
        );

    test('si la IMAGEN del QR da 404 en el servidor (la fila existe pero el archivo no) no se guarda nada y el motivo queda a la vista', () async {
      final cache = QrSucursalCache(
        dao: cacheDao,
        consultar: (id) async => id == 2 ? null : qr(id),
        descargar: (url) async => throw respuesta(404),
      );

      final r = await cache.actualizarConDetalle([1, 2]);

      expect(r.guardadas, isEmpty);
      expect(r.sinQr, [2]);
      expect(r.fallidas.keys, [1]);
      expect(r.fallidas[1], allOf(contains('error 404'), contains('volver a subirla')));
      expect(r.motivoDe(1), r.fallidas[1]);
      expect(r.motivoDe(2), contains('no tiene un QR configurado'));
      expect(r.motivoDe(9), isNull);
      expect(await filas(Schema.tablaQrSucursalCache), isEmpty);
    });

    test('los otros fallos también se explican: sin conexión, error del servidor e imagen vacía', () async {
      Future<String?> motivo(Future<List<int>> Function(String) descargar) async {
        final cache = QrSucursalCache(dao: cacheDao, consultar: (id) async => qr(id), descargar: descargar);
        return (await cache.actualizarConDetalle([1])).fallidas[1];
      }

      expect(await motivo((_) async => throw DioException(requestOptions: RequestOptions(path: '/x'), type: DioExceptionType.connectionError)), contains('sin conexión'));
      expect(await motivo((_) async => throw respuesta(500)), contains('error 500'));
      expect(await motivo((_) async => const <int>[]), contains('llegó vacía'));
      expect(await filas(Schema.tablaQrSucursalCache), isEmpty);
    });

    test('al actualizar el catálogo el proveedor AVISA que no pudo descargar el QR (ya no es silencioso) y lo recuerda por sucursal', () async {
      var imagenDisponible = false;
      final provider = CatalogoOfflineProvider(
        catalogoDao: catalogo,
        colaDao: cola,
        catalogoSync: _CatalogoSyncFalso(catalogo, [_fila(id: 1, sucursal: 1), _fila(id: 2, sucursal: 2), _fila(id: 3, sucursal: 3)]),
        qrCache: QrSucursalCache(
          dao: cacheDao,
          consultar: (id) async => id == 2 ? null : qr(id), // la 2 no tiene QR; la 1 y la 3 sí
          descargar: (url) async => imagenDisponible ? _png : throw respuesta(404),
        ),
      );

      await provider.actualizarDesdeServidor();

      expect(provider.ultimoMensaje, startsWith('Catálogo actualizado'));
      expect(provider.ultimoMensaje, contains('No se pudo descargar el QR de la sucursal 1'));
      expect(provider.ultimoMensaje, contains('error 404'));
      expect(provider.ultimoMensaje, contains('sucursal 3'));
      expect(provider.ultimoMensaje, isNot(contains('sucursal 2')), reason: 'una sucursal sin QR configurado no es un fallo de la descarga');
      expect(provider.motivoSinQr(1), contains('error 404'));
      expect(provider.motivoSinQr(2), contains('no tiene un QR configurado'));
      expect(await provider.qrDeSucursal(1), isNull);

      // el encargado vuelve a subir el QR: la siguiente actualización lo guarda y el motivo desaparece
      imagenDisponible = true;
      await provider.actualizarDesdeServidor();

      expect(provider.ultimoMensaje, isNot(contains('No se pudo descargar')));
      expect(provider.motivoSinQr(1), isNull);
      expect(provider.motivoSinQr(3), isNull);
      expect(provider.motivoSinQr(2), contains('no tiene un QR configurado'));
      expect(await provider.qrDeSucursal(1), _png);
    });

    test('un QR inactivo o sin imagen no se guarda', () async {
      final cache = QrSucursalCache(dao: cacheDao, consultar: (id) async => id == 1 ? qr(1, activo: false) : qr(2, url: ''), descargar: (_) async => _png);

      expect(await cache.actualizar([1, 2]), 0);
      expect(await filas(Schema.tablaQrSucursalCache), isEmpty);
    });

    test('al actualizar el catálogo con red, el proveedor guarda el QR de cada sucursal del catálogo', () async {
      final pedidos = <int>[];
      final provider = CatalogoOfflineProvider(
        catalogoDao: catalogo,
        colaDao: cola,
        catalogoSync: _CatalogoSyncFalso(catalogo, [_fila(id: 1, sucursal: 1), _fila(id: 2, sucursal: 7), _fila(id: 3, sucursal: 7)]),
        qrCache: QrSucursalCache(
          dao: cacheDao,
          consultar: (id) async {
            pedidos.add(id);
            return qr(id);
          },
          descargar: (_) async => _png,
        ),
      );

      await provider.actualizarDesdeServidor();

      expect(pedidos.toSet(), {1, 7});
      final guardadas = {for (final f in await filas(Schema.tablaQrSucursalCache)) f['sucursal_id']: f['imagen_url']};
      expect(guardadas, {1: '/uploads/qr/s.png', 7: '/uploads/qr/s.png'}, reason: 'cada sucursal del catálogo queda con la ruta de su QR');
      expect(await provider.qrDeSucursal(7), _png);
      expect(await provider.qrDeSucursal(1), _png);
      expect(await provider.qrDeSucursal(9), isNull);
    });

    test('si no se pudo guardar el QR la actualización del catálogo igual termina bien (y sin caché el proveedor no falla)', () async {
      final conFallo = CatalogoOfflineProvider(
        catalogoDao: catalogo,
        colaDao: cola,
        catalogoSync: _CatalogoSyncFalso(catalogo, [_fila(id: 1)]),
        qrCache: QrSucursalCache(dao: cacheDao, consultar: (_) async => throw Exception('sin red'), descargar: (_) async => _png),
      );
      await conFallo.actualizarDesdeServidor();
      expect(conFallo.productos, hasLength(1));
      expect(conFallo.error, isNull);

      final sinCache = CatalogoOfflineProvider(catalogoDao: catalogo, colaDao: cola, catalogoSync: _CatalogoSyncFalso(catalogo, [_fila(id: 1)]));
      await sinCache.actualizarDesdeServidor();
      expect(await sinCache.qrDeSucursal(1), isNull);
    });
  });

  // =====================================================================================================================
  group('migración v7 → v8: la cola y las operaciones admiten VENTA_CLIENTE_QR', () {
    late String ruta;

    setUp(() => ruta = '${Directory.systemTemp.path}${Platform.pathSeparator}smartlook_mig8_${DateTime.now().microsecondsSinceEpoch}.db');

    tearDown(() async {
      for (final sufijo in ['', '-journal', '-wal', '-shm']) {
        final f = File('$ruta$sufijo');
        if (await f.exists()) await f.delete();
      }
    });

    /// El esquema tal como era en v7: sin el tipo VENTA_CLIENTE_QR (ni su CHECK) y sin `qr_sucursal_cache`.
    List<String> ddlV7() => [
          for (final s in Schema.ddl)
            if (!s.contains('qr_sucursal_cache'))
              s
                  .replaceAll(", 'VENTA_CLIENTE_QR'", '')
                  .replaceAll(RegExp(r"\n\s*CHECK \(tipo_operacion <> 'VENTA_CLIENTE_QR'[^\n]*\n?"), '\n'),
        ];

    test('lo que ya estaba se conserva, las tablas aceptan el tipo nuevo (con sus reglas) y nace la caché del QR', () async {
      final v7 = await openDatabase(
        ruta,
        version: 7,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) async {
          for (final s in ddlV7()) {
            await db.execute(s);
          }
        },
      );
      Future<void> insertarCompra(Database db, String uuid, {int? cliente = _cliente}) => db.insert('operaciones_locales', {
            'uuid': uuid, 'tipo_operacion': 'VENTA_CLIENTE_QR', 'sucursal_id': 1, 'cliente_id': cliente, 'total_centavos': 100,
            'fecha': '2026-11-10T10:00:00Z', 'estado': 'pendiente_sync',
          });
      await v7.insert('operaciones_locales', {
        'uuid': 'v1', 'tipo_operacion': 'VENTA_CONTADO', 'sucursal_id': 1, 'cajero_id': 7, 'total_centavos': 1999,
        'fecha': '2026-11-01T10:00:00Z', 'estado': 'pendiente_sync',
      });
      await v7.insert('operaciones_locales_items', {'operacion_uuid': 'v1', 'producto_id': 101, 'nombre_producto': 'Camiseta', 'cantidad': 1, 'precio_unitario_centavos': 1999});
      await v7.insert('sync_queue', {
        'id': 'q1', 'tipo_operacion': 'VENTA_CONTADO', 'operacion_uuid': 'v1', 'payload_json': '{"sucursal_id":1,"items":[]}',
        'estado': 'pendiente', 'intentos': 2, 'fecha_creacion': '2026-11-01T10:00:00Z',
      });
      await expectLater(insertarCompra(v7, 'x0'), throwsA(anything), reason: 'en v7 el tipo todavía no existe'); // la migración hace falta
      await v7.close();

      final db = await AppDatabase.abrir(ruta); // → onUpgrade(7, 8)
      final nuevo = AppDatabase.conBaseDeDatos(db);
      addTearDown(nuevo.cerrar);

      expect(Sqflite.firstIntValue(await db.rawQuery('PRAGMA user_version')), 8);
      expect(Sqflite.firstIntValue(await db.rawQuery('PRAGMA foreign_keys')), 1);
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      // lo anterior sigue ahí, con sus ítems y su cola
      expect((await db.query('operaciones_locales', where: "uuid = 'v1'")).single['estado'], 'pendiente_sync');
      expect(await db.query('operaciones_locales_items', where: "operacion_uuid = 'v1'"), hasLength(1));
      final q1 = (await db.query('sync_queue', where: "id = 'q1'")).single;
      expect((q1['operacion_uuid'], q1['intentos']), ('v1', 2));

      // ahora sí acepta el tipo nuevo, con sus reglas
      await insertarCompra(db, 'c1');
      await db.insert('sync_queue', {
        'id': 'q2', 'tipo_operacion': 'VENTA_CLIENTE_QR', 'operacion_uuid': 'c1', 'payload_json': '{}', 'estado': 'pendiente', 'fecha_creacion': '2026-11-10T10:00:00Z',
      });
      await expectLater(insertarCompra(db, 'c2', cliente: null), throwsA(anything), reason: 'una compra del cliente exige cliente');
      await expectLater(
        db.insert('operaciones_locales', {
          'uuid': 'c3', 'tipo_operacion': 'VENTA_CLIENTE_QR', 'sucursal_id': 1, 'cliente_id': _cliente, 'cajero_id': 7, 'total_centavos': 1,
          'fecha': '2026-11-10T10:00:00Z', 'estado': 'pendiente_sync',
        }),
        throwsA(anything),
        reason: 'y no lleva cajero',
      );
      // y la caché del QR de la sucursal ya existe
      await QrSucursalCacheDao(appDatabase: nuevo).guardar(1, _png);
      expect(await QrSucursalCacheDao(appDatabase: nuevo).obtener(1), _png);
    });
  });

  // =====================================================================================================================
  group('hoja "Comprar" (widget)', () {
    Future<Future<CompraQr?> Function()> abrir(WidgetTester tester, {Uint8List? qr, SelectorQr? selector, CatalogoItem? producto, String? motivoSinQr}) async {
      CompraQr? resultado;
      var cerrada = false;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 1600);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                resultado = await mostrarCompraQr(
                  context,
                  producto: producto ?? _item(),
                  obtenerQr: () async => qr,
                  selector: selector ?? (_) async => QrElegido(_png, 'comprobante.png'),
                  motivoSinQr: motivoSinQr,
                );
                cerrada = true;
              },
              child: const Text('abrir'),
            ),
          ),
        ),
      ));
      return () async {
        await tester.pumpAndSettle();
        expect(cerrada, isTrue);
        return resultado;
      };
    }

    Future<void> mostrar(WidgetTester tester) async {
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
    }

    testWidgets('muestra el QR de la sucursal que estaba guardado en el celular, el total y "Pago por QR"', (tester) async {
      await abrir(tester, qr: _png);
      await mostrar(tester);

      expect(find.text('Pago por QR'), findsOneWidget);
      expect(find.byKey(const Key('qr_sucursal')), findsOneWidget);
      expect(find.byKey(const Key('sin_qr')), findsNothing);
      expect(find.text('Total: \$100.00'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const Key('confirmar_compra'))).onPressed, isNull, reason: 'sin comprobante no se puede confirmar');
    });

    testWidgets('si el QR nunca se descargó lo dice y no inventa ninguna imagen', (tester) async {
      await abrir(tester, qr: null);
      await mostrar(tester);

      expect(find.byKey(const Key('sin_qr')), findsOneWidget);
      expect(find.textContaining('Conéctate a internet una vez'), findsOneWidget);
      expect(find.byKey(const Key('qr_sucursal')), findsNothing);
    });

    testWidgets('si no hay QR guardado, la hoja explica POR QUÉ (el motivo que averiguó la última actualización del catálogo)', (tester) async {
      await abrir(tester, qr: null, motivoSinQr: 'la imagen del QR no está en el servidor (error 404): el encargado debe volver a subirla');
      await mostrar(tester);

      expect(find.byKey(const Key('sin_qr')), findsOneWidget);
      expect(find.byKey(const Key('motivo_sin_qr')), findsOneWidget);
      expect(find.textContaining('error 404'), findsOneWidget);
    });

    testWidgets('con el QR guardado no aparece ningún motivo', (tester) async {
      await abrir(tester, qr: _png, motivoSinQr: 'dato viejo');
      await mostrar(tester);

      expect(find.byKey(const Key('motivo_sin_qr')), findsNothing);
    });

    testWidgets('Subir comprobante habilita "Confirmar compra" y devuelve la cantidad y el comprobante elegido', (tester) async {
      final resultado = await abrir(tester, qr: _png);
      await mostrar(tester);

      await tester.tap(find.byKey(const Key('subir_comprobante')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('vista_comprobante')), findsOneWidget);
      expect(find.text('Cambiar comprobante'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('confirmar_compra')));
      expect(tester.widget<FilledButton>(find.byKey(const Key('confirmar_compra'))).onPressed, isNotNull);
      await tester.tap(find.byKey(const Key('confirmar_compra')));

      final compra = (await resultado())!;
      expect(compra.cantidad, 1);
      expect(compra.comprobante, _png);
      expect(compra.nombreComprobante, 'comprobante.png');
    });

    testWidgets('si el cliente cancela la elección del comprobante sigue sin poder confirmar', (tester) async {
      await abrir(tester, qr: _png, selector: (_) async => null);
      await mostrar(tester);

      await tester.tap(find.byKey(const Key('subir_comprobante')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('vista_comprobante')), findsNothing);
      expect(tester.widget<FilledButton>(find.byKey(const Key('confirmar_compra'))).onPressed, isNull);
    });

    testWidgets('la cantidad sube hasta el stock disponible y el total la acompaña', (tester) async {
      final resultado = await abrir(tester, qr: _png, producto: _item(stock: 3));
      await mostrar(tester);

      expect(tester.widget<IconButton>(find.byKey(const Key('menos'))).onPressed, isNull);
      await tester.tap(find.byKey(const Key('mas')));
      await tester.tap(find.byKey(const Key('mas')));
      await tester.pump();
      expect(find.text('3'), findsOneWidget);
      expect(find.text('Total: \$300.00'), findsOneWidget);
      expect(tester.widget<IconButton>(find.byKey(const Key('mas'))).onPressed, isNull, reason: 'no hay más stock');

      await tester.tap(find.byKey(const Key('subir_comprobante')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('confirmar_compra')));
      await tester.tap(find.byKey(const Key('confirmar_compra')));
      expect((await resultado())!.cantidad, 3);
    });
  });

  // =====================================================================================================================
  group('catálogo offline: "Comprar" solo sin conexión (y "Reservar" sigue)', () {
    Future<_CatalogoPantalla> montar(WidgetTester tester, {required bool conRed, SelectorQr? selector}) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 1800);
      addTearDown(tester.view.reset);
      final catalogoFalso = _CatalogoPantalla([_item(id: 1, stock: 5), _item(id: 2, stock: 0)]);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<CatalogoOfflineProvider>.value(value: catalogoFalso),
            ChangeNotifierProvider<SuscripcionesProvider>(create: (_) => _SuscripcionesFalso()),
            ChangeNotifierProvider<AuthProvider>(create: (_) => _AuthFalso()),
            ChangeNotifierProvider<ConectividadProvider>(
              create: (_) => ConectividadProvider(cambios: const Stream.empty(), consultar: () async => [conRed ? ConnectivityResult.wifi : ConnectivityResult.none]),
            ),
            Provider<SyncService>(create: (_) => _SyncFalso()),
          ],
          child: MaterialApp(home: CatalogoOfflineScreen(selectorComprobante: selector)),
        ),
      );
      await tester.pump();
      await tester.pump();
      return catalogoFalso;
    }

    testWidgets('SIN conexión el producto con stock ofrece "Comprar" (y "Reservar" como segunda opción)', (tester) async {
      await montar(tester, conRed: false);

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('comprar_1')), findsOneWidget);
      expect(find.text('Comprar'), findsOneWidget);
      expect(find.byKey(const Key('reservar_1')), findsOneWidget);
      expect(find.text('Reservar'), findsOneWidget);
      expect(find.text('Avísame cuando llegue'), findsOneWidget); // el agotado sigue igual
    });

    testWidgets('CON conexión no cambia nada: solo "Reservar"', (tester) async {
      await montar(tester, conRed: true);

      expect(tester.takeException(), isNull);
      expect(find.text('Reservar'), findsOneWidget);
      expect(find.text('Comprar'), findsNothing);
      expect(find.byKey(const Key('comprar_1')), findsNothing);
    });

    testWidgets('Comprar → ve el QR de la sucursal → sube el comprobante → confirma: la compra se guarda con el comprobante', (tester) async {
      final catalogoFalso = await montar(tester, conRed: false, selector: (_) async => QrElegido(_png, 'transferencia.png'));

      await tester.tap(find.byKey(const Key('comprar_1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('qr_sucursal')), findsOneWidget);
      await tester.tap(find.byKey(const Key('subir_comprobante')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('confirmar_compra')));
      await tester.tap(find.byKey(const Key('confirmar_compra')));
      await tester.pumpAndSettle();

      expect(catalogoFalso.compras, hasLength(1));
      final c = catalogoFalso.compras.single;
      expect((c.inventarioId, c.clienteId, c.cantidad, c.nombre), (1, 55, 1, 'transferencia.png'));
      expect(c.comprobante, _png);
      expect(find.textContaining('Compra guardada'), findsOneWidget);
    });
  });
}

// ---------------------------------------------------------------------------------------------------------------------
// Dobles de prueba
// ---------------------------------------------------------------------------------------------------------------------

/// "Descarga" el catálogo escribiendo [filas] en SQLite (no sale a la red).
class _CatalogoSyncFalso extends CatalogoSyncService {
  _CatalogoSyncFalso(this._dao, this._filas) : super(dao: _dao);

  final CatalogoLocalDao _dao;
  final List<Map<String, Object?>> _filas;

  @override
  Future<ResultadoDescargaCatalogo> descargarCatalogoDesdeServidor({int? sucursalId}) async {
    await _dao.guardarLoteCatalogo(_filas);
    return ResultadoDescargaCatalogo(registros: _filas.length);
  }
}

class _Compra {
  _Compra(this.inventarioId, this.clienteId, this.cantidad, this.comprobante, this.nombre);

  final int inventarioId, clienteId, cantidad;
  final List<int> comprobante;
  final String nombre;
}

class _CatalogoPantalla extends CatalogoOfflineProvider {
  _CatalogoPantalla(this._items);

  final List<CatalogoItem> _items;
  final compras = <_Compra>[];
  String? _mensaje;

  @override
  List<CatalogoItem> get productos => _items;

  @override
  bool get soportado => false;

  @override
  String? get ultimoMensaje => _mensaje;

  @override
  Future<void> cargar() async {}

  @override
  Future<Uint8List?> qrDeSucursal(int sucursalId) async => _png;

  @override
  Future<bool> comprarConQr(CatalogoItem producto, int clienteId, {required int cantidad, required List<int> comprobante, String nombreComprobante = 'comprobante.jpg'}) async {
    compras.add(_Compra(producto.inventarioId, clienteId, cantidad, comprobante, nombreComprobante));
    _mensaje = 'Compra guardada en el dispositivo.';
    return true;
  }
}

class _SuscripcionesFalso extends SuscripcionesProvider {
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
  Usuario? get usuario => Usuario(id: 55, nombre: 'Cliente', email: 'c@t.bo', rol: 'cliente', activo: true);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
