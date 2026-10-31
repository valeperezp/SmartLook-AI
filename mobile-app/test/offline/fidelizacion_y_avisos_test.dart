import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartlook_mobile/core/config/offline_config.dart';
import 'package:smartlook_mobile/core/database/app_database.dart';
import 'package:smartlook_mobile/core/database/schema.dart';
import 'package:smartlook_mobile/features/offline/data/catalogo_local_dao.dart';
import 'package:smartlook_mobile/features/offline/data/devolucion_dao.dart';
import 'package:smartlook_mobile/features/offline/data/puntos_dao.dart';
import 'package:smartlook_mobile/features/offline/data/suscripcion_stock_dao.dart';
import 'package:smartlook_mobile/features/offline/data/sync_queue_dao.dart';
import 'package:smartlook_mobile/features/offline/data/turno_caja_dao.dart';
import 'package:smartlook_mobile/features/offline/models/catalogo_item.dart';
import 'package:smartlook_mobile/features/offline/providers/puntos_provider.dart';
import 'package:smartlook_mobile/features/offline/providers/suscripciones_provider.dart';
import 'package:smartlook_mobile/features/offline/providers/venta_offline_provider.dart';
import 'package:smartlook_mobile/features/offline/services/sync_service.dart';
import 'package:sqflite/sqflite.dart' show Sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'schema_v1_fixture.dart';

const _camiseta = 101, _jean = 103, _falda = 107, _short = 109;
const _cliente = 55;

Map<String, dynamic> _item(int productoId, int cantidad) {
  const variantes = {101: (2, 1), 103: (4, 3), 107: (1, 5), 109: (2, 5)};
  final v = variantes[productoId]!;
  return {'producto_id': productoId, 'talla_id': v.$1, 'color_id': v.$2, 'cantidad': cantidad};
}

Map<String, dynamic> _filaCatalogo(int inventarioId, int productoId, int? talla, int? color, int stock) => {
      'inventario_id': inventarioId,
      'sucursal_id': 1,
      'producto_id': productoId,
      'talla_id': talla,
      'color_id': color,
      'nombre_producto': 'Falda plisada',
      'precio_centavos': 3999,
      'cantidad_disponible': stock,
    };

void main() {
  late AppDatabase appDb;
  late SyncQueueDao cola;
  late TurnoCajaDao turnos;
  late DevolucionDao devoluciones;
  late CatalogoLocalDao catalogo;
  late PuntosDao puntos;
  late SuscripcionStockDao avisos;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    appDb = AppDatabase.conBaseDeDatos(await AppDatabase.abrir(inMemoryDatabasePath));
    cola = SyncQueueDao(appDatabase: appDb);
    turnos = TurnoCajaDao(appDatabase: appDb);
    devoluciones = DevolucionDao(appDatabase: appDb);
    catalogo = CatalogoLocalDao(appDatabase: appDb);
    puntos = PuntosDao(appDatabase: appDb);
    avisos = SuscripcionStockDao(appDatabase: appDb);
  });

  tearDown(() => appDb.cerrar());

  Future<int> contar(String tabla, [String? donde]) async {
    final db = (await appDb.database)!;
    return Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM $tabla ${donde ?? ''}'))!;
  }

  // ===========================================================================
  group('configuración', () {
    test('1 punto por cada \$10, redondeando hacia abajo', () {
      expect(OfflineConfig.centavosPorPunto, 1000);
      expect(OfflineConfig.puntosPara(999), 0);
      expect(OfflineConfig.puntosPara(1000), 1);
      expect(OfflineConfig.puntosPara(2999), 2);
      expect(OfflineConfig.puntosPara(9997), 9);
    });
  });

  // ===========================================================================
  group('CU16 · avisos de stock (Avísame cuando llegue)', () {
    Future<ResultadoSuscripcion> suscribir({int cliente = _cliente, int producto = _falda, int? talla = 1, int? color = 5, int? sucursal = 1}) =>
        avisos.crearSuscripcion(clienteId: cliente, productoId: producto, tallaId: talla, colorId: color, sucursalId: sucursal, descripcion: 'Falda plisada · S · Negro');

    test('crea la suscripción y no duplica una pendiente igual', () async {
      final a = await suscribir();
      final b = await suscribir();

      expect(a.creada, isTrue);
      expect(b.creada, isFalse);
      expect(b.id, a.id);
      expect(await contar(Schema.tablaSuscripcionesStock), 1);
      expect((await avisos.obtenerSuscripcionesPendientes(_cliente)).single['estado'], 'pendiente');
    });

    test('otra talla, otro cliente u otra sucursal sí son suscripciones distintas', () async {
      await suscribir();
      expect((await suscribir(talla: 2)).creada, isTrue);
      expect((await suscribir(cliente: 99)).creada, isTrue);
      expect((await suscribir(sucursal: 2)).creada, isTrue);
      expect(await contar(Schema.tablaSuscripcionesStock), 4);
      expect(await avisos.obtenerSuscripcionesPendientes(_cliente), hasLength(3));
    });

    test('dos pulsaciones simultáneas no crean dos avisos', () async {
      final r = await Future.wait([suscribir(), suscribir()]);
      expect(r.where((x) => x.creada), hasLength(1));
      expect(await contar(Schema.tablaSuscripcionesStock), 1);
    });

    test('al refrescar el catálogo con stock marca como notificado y lo devuelve', () async {
      await catalogo.guardarLoteCatalogo([_filaCatalogo(1, _falda, 1, 5, 0)]);
      await suscribir();

      final notificados = await catalogo.guardarLoteCatalogo([_filaCatalogo(1, _falda, 1, 5, 6)]);

      expect(notificados, hasLength(1));
      expect(notificados.single['descripcion'], 'Falda plisada · S · Negro');
      final s = (await (await appDb.database)!.query(Schema.tablaSuscripcionesStock)).single;
      expect(s['estado'], 'notificado');
      expect(s['fecha_notificacion'], isNotNull);
      expect(s['visto'], 0);
      expect(await avisos.obtenerSuscripcionesPendientes(_cliente), isEmpty);
      expect(await avisos.obtenerAvisosSinVer(_cliente), hasLength(1));
    });

    test('no notifica si la prenda sigue sin stock', () async {
      await catalogo.guardarLoteCatalogo([_filaCatalogo(1, _falda, 1, 5, 0)]);
      await suscribir();

      final notificados = await catalogo.guardarLoteCatalogo([_filaCatalogo(1, _falda, 1, 5, 0)]);

      expect(notificados, isEmpty);
      expect((await avisos.obtenerSuscripcionesPendientes(_cliente)), hasLength(1));
      expect(await avisos.obtenerAvisosSinVer(_cliente), isEmpty);
    });

    test('solo notifica la variante que esperaba (otra talla con stock no cuenta)', () async {
      await catalogo.guardarLoteCatalogo([_filaCatalogo(1, _falda, 1, 5, 0), _filaCatalogo(2, _falda, 2, 5, 0)]);
      await suscribir(talla: 1); // espera la talla S

      // llega stock de la talla M, la S sigue agotada
      expect(await catalogo.guardarLoteCatalogo([_filaCatalogo(1, _falda, 1, 5, 0), _filaCatalogo(2, _falda, 2, 5, 9)]), isEmpty);
      // un producto distinto con stock tampoco
      expect(await catalogo.guardarLoteCatalogo([_filaCatalogo(1, _falda, 1, 5, 0), _filaCatalogo(3, 999, 1, 5, 9)]), isEmpty);
      // ahora sí llega la S
      expect(await catalogo.guardarLoteCatalogo([_filaCatalogo(1, _falda, 1, 5, 4)]), hasLength(1));
    });

    test('una suscripción sin talla ni color avisa con cualquier variante; otra sucursal no cuenta', () async {
      await catalogo.guardarLoteCatalogo([_filaCatalogo(1, _falda, 1, 5, 0)]);
      await suscribir(talla: null, color: null);
      await suscribir(cliente: 99, sucursal: 2); // espera en la sucursal 2

      final notificados = await catalogo.guardarLoteCatalogo([_filaCatalogo(1, _falda, 1, 5, 3)]);

      expect(notificados.map((n) => n['cliente_id']), [_cliente]);
    });

    test('un aviso ya notificado no se repite, y se puede volver a suscribir', () async {
      await catalogo.guardarLoteCatalogo([_filaCatalogo(1, _falda, 1, 5, 0)]);
      await suscribir();
      await catalogo.guardarLoteCatalogo([_filaCatalogo(1, _falda, 1, 5, 6)]);
      expect(await catalogo.guardarLoteCatalogo([_filaCatalogo(1, _falda, 1, 5, 7)]), isEmpty); // ya notificado
      expect((await suscribir()).creada, isTrue); // nuevo aviso tras notificado
    });

    test('marcarNotificadas por variante y marcarVistos', () async {
      final r = await suscribir();
      expect(await avisos.marcarNotificadas(_falda, 2, 5, 1), isEmpty); // otra talla
      final cambiadas = await avisos.marcarNotificadas(_falda, 1, 5, 1);
      expect(cambiadas.single['id'], r.id);
      expect(await avisos.obtenerAvisosSinVer(_cliente), hasLength(1));
      await avisos.marcarVistos([r.id]);
      expect(await avisos.obtenerAvisosSinVer(_cliente), isEmpty);
    });

    test('cancelar y expirar', () async {
      final a = await suscribir();
      final b = await suscribir(talla: 2);
      expect(await avisos.cancelar(a.id), isTrue);
      expect(await avisos.cancelar(a.id), isFalse); // ya no estaba pendiente

      expect(await avisos.expirarAntiguas(dias: 30, ahora: DateTime.now().add(const Duration(days: 10))), 0);
      expect(await avisos.expirarAntiguas(dias: 30, ahora: DateTime.now().add(const Duration(days: 40))), 1);
      expect(await avisos.obtenerSuscripcionesPendientes(_cliente), isEmpty);
      expect((await (await appDb.database)!.query(Schema.tablaSuscripcionesStock, where: 'id = ?', whereArgs: [b.id])).single['estado'], 'expirado');
    });

    test('SuscripcionesProvider: no suscribe lo que ya tiene stock, y el aviso se muestra una sola vez', () async {
      final provider = SuscripcionesProvider(dao: avisos);
      await catalogo.guardarLoteCatalogo([_filaCatalogo(1, _falda, 1, 5, 0), _filaCatalogo(2, _jean, 4, 3, 5)]);
      final filas = (await catalogo.obtenerProductos()).map(CatalogoItem.fromMap).toList();
      final agotada = filas.firstWhere((p) => p.productoId == _falda);
      final conStock = filas.firstWhere((p) => p.productoId == _jean);

      expect(await provider.suscribirse(conStock, _cliente), isFalse);
      expect(await provider.suscribirse(agotada, _cliente), isTrue);
      expect(provider.estaSuscrito(agotada), isTrue);
      expect(await provider.suscribirse(agotada, _cliente), isTrue);
      expect(provider.mensaje, contains('Ya estabas'));
      expect(provider.pendientes, hasLength(1));

      await catalogo.guardarLoteCatalogo([_filaCatalogo(1, _falda, 1, 5, 6)]);
      final mensajes = await provider.revisarAvisos(_cliente);
      expect(mensajes.single, allOf(contains('¡Llegó stock de'), contains('Falda plisada'), contains('que esperabas')));
      expect(await provider.revisarAvisos(_cliente), isEmpty); // ya visto
      expect(provider.estaSuscrito(agotada), isFalse);
    });
  });

  // ===========================================================================
  group('CU17 · puntos de fidelización', () {
    late VentaOfflineProvider pos;
    late String turno;

    setUp(() async {
      pos = VentaOfflineProvider(catalogoDao: catalogo, colaDao: cola);
      await pos.cargarDatosMock(1);
      turno = await turnos.abrirTurno(7, 1, 0);
    });

    /// Vende 2 camisetas ($19.99) + 1 jean ($59.99) = $99.97 → 9 puntos, a [clienteId] (o a nadie).
    Future<String> vender({int? clienteId = _cliente}) async {
      pos
        ..agregarProducto(pos.productos.firstWhere((p) => p.productoId == _camiseta))
        ..agregarProducto(pos.productos.firstWhere((p) => p.productoId == _camiseta))
        ..agregarProducto(pos.productos.firstWhere((p) => p.productoId == _jean));
      expect(await pos.procesarVenta(cajeroId: 7, sucursalId: 1, turnoUuid: turno, clienteId: clienteId), isTrue);
      return (await (await appDb.database)!.query(Schema.tablaOperaciones, columns: ['uuid'], orderBy: 'rowid DESC', limit: 1)).single['uuid'] as String;
    }

    Future<String> devolver(String venta, List<Map<String, dynamic>> items) async =>
        (await devoluciones.registrarDevolucion(venta, 'DEVOLUCION', items, [], turno)).id;

    test('otorgarPuntos: 1 por cada \$10, acumula en el saldo y no registra nada si no llega a un punto', () async {
      expect(await puntos.otorgarPuntos(_cliente, 'a', 2999), 2);
      expect(await puntos.otorgarPuntos(_cliente, 'b', 999), 0);
      expect(await puntos.otorgarPuntos(_cliente, 'c', 1000), 1);

      expect(await puntos.obtenerSaldo(_cliente), 3);
      expect(await puntos.obtenerSaldo(404), 0); // cliente sin puntos
      expect(await contar(Schema.tablaMovimientosPuntos), 2);
    });

    test('una venta con cliente le otorga puntos y deja el movimiento en la cola', () async {
      final venta = await vender();

      expect(await puntos.obtenerSaldo(_cliente), 9);
      final db = (await appDb.database)!;
      final m = (await db.query(Schema.tablaMovimientosPuntos)).single;
      expect((m['tipo'], m['cantidad'], m['operacion_uuid'], m['venta_uuid'], m['estado_sync']), ('ganado', 9, venta, venta, 'pendiente'));
      final q = (await db.query(Schema.tablaSyncQueue, where: "tipo_operacion = 'PUNTOS_OTORGADOS'")).single;
      expect(q['estado'], 'pendiente');
      expect(q['movimiento_puntos_id'], m['id']);
      expect(q['operacion_uuid'], isNull);
      expect(q['payload_json'] as String, allOf(contains('"cantidad":9'), contains('"cliente_id":55')));
    });

    test('sin cliente, o en una reserva, no hay puntos', () async {
      await vender(clienteId: null);
      await cola.guardarOperacionOffline(
        {'sucursal_id': 1, 'items': [{'producto_id': _camiseta, 'talla_id': 2, 'color_id': 1, 'nombre_producto': 'x', 'cantidad': 1, 'precio_unitario_centavos': 99999}]},
        'reserva', Schema.tipoReservaCliente, _cliente,
      );
      expect(await contar(Schema.tablaMovimientosPuntos), 0);
      expect(await contar(Schema.tablaPuntosCliente), 0);
      expect(await contar(Schema.tablaSyncQueue, "WHERE tipo_operacion LIKE 'PUNTOS%'"), 0);
    });

    test('si la venta falla no quedan puntos a medias (atomicidad)', () async {
      await turnos.cerrarTurno(turno, 0);
      pos.agregarProducto(pos.productos.firstWhere((p) => p.productoId == _camiseta));
      expect(await pos.procesarVenta(cajeroId: 7, sucursalId: 1, turnoUuid: turno, clienteId: _cliente), isFalse); // turno cerrado

      expect(await puntos.obtenerSaldo(_cliente), 0);
      expect(await contar(Schema.tablaMovimientosPuntos), 0);
    });

    test('devolución parcial resta puntos proporcionales; devolver todo deja exactamente lo ganado en cero', () async {
      final venta = await vender(); // $99.97 → 9 puntos
      expect(await puntos.obtenerSaldo(_cliente), 9);

      await devolver(venta, [_item(_jean, 1)]); // $59.99 de $99.97 → round(9 × 5999/9997) = 5
      expect(await puntos.obtenerSaldo(_cliente), 4);

      await devolver(venta, [_item(_camiseta, 2)]); // en total ya se devolvió todo → se pierde el resto (4)
      expect(await puntos.obtenerSaldo(_cliente), 0);

      final m = await (await appDb.database)!.query(Schema.tablaMovimientosPuntos, where: "tipo = 'perdido'", orderBy: 'rowid');
      expect(m.map((x) => x['cantidad']), [5, 4]);
      expect(await contar(Schema.tablaSyncQueue, "WHERE tipo_operacion = 'PUNTOS_RESTADOS'"), 2);
    });

    test('devolver de a una prenda en varias devoluciones suma exactamente los puntos ganados', () async {
      final venta = await vender();
      await devolver(venta, [_item(_camiseta, 1)]);
      await devolver(venta, [_item(_camiseta, 1)]);
      await devolver(venta, [_item(_jean, 1)]);
      expect(await puntos.obtenerSaldo(_cliente), 0);
      final perdidos = await (await appDb.database)!.rawQuery("SELECT SUM(cantidad) AS n FROM movimientos_puntos WHERE tipo = 'perdido'");
      expect(perdidos.single['n'], 9);
    });

    test('un cambio también resta los puntos de lo devuelto', () async {
      final venta = await vender();
      await devoluciones.registrarDevolucion(venta, 'CAMBIO', [_item(_jean, 1)], [_item(_short, 1)], turno); // jean por short

      expect(await puntos.obtenerSaldo(_cliente), 4); // 9 - round(9 × 5999/9997)
    });

    test('devolver una venta hecha sin cliente no toca ningún saldo', () async {
      final sinCliente = await vender(clienteId: null);
      await devolver(sinCliente, [_item(_camiseta, 1)]);
      expect(await contar(Schema.tablaMovimientosPuntos), 0);
      expect(await contar(Schema.tablaPuntosCliente), 0);
    });

    test('el saldo nunca queda negativo (se descuenta como máximo lo que hay)', () async {
      final venta = await vender(); // 9 puntos
      final db = (await appDb.database)!;
      await db.update(Schema.tablaPuntosCliente, {'saldo': 2}, where: 'cliente_id = ?', whereArgs: [_cliente]); // ya gastó 7

      await devolver(venta, [_item(_jean, 1), _item(_camiseta, 2)]); // devolución total: correspondería perder 9

      expect(await puntos.obtenerSaldo(_cliente), 0);
      expect((await db.query(Schema.tablaMovimientosPuntos, where: "tipo = 'perdido'")).single['cantidad'], 2); // lo que había
      // y la propia tabla lo impide aunque se salte el DAO
      await expectLater(db.update(Schema.tablaPuntosCliente, {'saldo': -1}, where: 'cliente_id = ?', whereArgs: [_cliente]), throwsA(anything));
    });

    test('restarPuntos suelto también es proporcional y nunca negativo', () async {
      final venta = await vender();
      expect(await puntos.restarPuntos(_cliente, venta, 5999), 5);
      expect(await puntos.obtenerSaldo(_cliente), 4);
      expect(await puntos.restarPuntos(_cliente, venta, 0), 0);
    });

    test('devolución rechazada: los puntos que se habían restado vuelven', () async {
      final venta = await vender();
      final dev = await devolver(venta, [_item(_jean, 1)]);
      expect(await puntos.obtenerSaldo(_cliente), 4);

      await devoluciones.marcarRechazada(dev, 'Rechazada por el servidor');

      expect(await puntos.obtenerSaldo(_cliente), 9);
      final db = (await appDb.database)!;
      expect((await db.query(Schema.tablaMovimientosPuntos, where: "tipo = 'perdido'")).single['estado_sync'], 'rechazado');
      expect((await db.query(Schema.tablaSyncQueue, where: "tipo_operacion = 'PUNTOS_RESTADOS'")).single['estado'], 'rechazado');
      expect((await puntos.listarMovimientos(_cliente)).map((m) => m['tipo']), ['ganado']); // el anulado no se lista
    });

    test('venta rechazada: sus puntos se anulan', () async {
      final venta = await vender();
      expect(await puntos.obtenerSaldo(_cliente), 9);

      await cola.marcarRechazada(venta, 'Stock insuficiente');

      expect(await puntos.obtenerSaldo(_cliente), 0);
      expect((await (await appDb.database)!.query(Schema.tablaSyncQueue, where: "tipo_operacion = 'PUNTOS_OTORGADOS'")).single['estado'], 'rechazado');
    });

    test('PuntosProvider muestra saldo y movimientos', () async {
      await vender();
      final provider = PuntosProvider(dao: puntos);
      await provider.cargar(_cliente);
      expect(provider.saldo, 9);
      expect(provider.movimientos.single.delta, 9);
      expect(provider.movimientos.single.sincronizado, isFalse);
    });

    group('sincronización de puntos', () {
      SyncService servicio({EnviarLote? enviar, double Function()? sorteo}) => SyncService(
            colaDao: cola,
            turnoDao: turnos,
            devolucionDao: devoluciones,
            puntosDao: puntos,
            hayRed: () async => true,
            enviar: enviar,
            sorteo: sorteo ?? () => 0.9,
          );

      Map<String, dynamic> ok(Map<String, dynamic> lote) => {
            'resultados': [
              for (final clave in ['operaciones', 'devoluciones', 'movimientos_puntos', 'cierres_caja'])
                for (final o in (lote[clave] as List? ?? const [])) {'uuid': o['uuid'], 'status': 'ok', 'id_servidor': 7},
            ],
          };

      test('los puntos viajan después de su venta y de su devolución', () async {
        final venta = await vender();
        await devolver(venta, [_item(_jean, 1)]);
        final claves = <String>[];
        Map<String, dynamic>? lotePuntos;

        final r = await servicio(enviar: (lote) async {
          claves.add(['operaciones', 'devoluciones', 'movimientos_puntos'].firstWhere(lote.containsKey));
          if (lote.containsKey('movimientos_puntos')) lotePuntos = lote;
          return ok(lote);
        }).sincronizarPendientes();

        expect(claves, ['operaciones', 'devoluciones', 'movimientos_puntos']);
        expect(r.sincronizadas, 4); // venta, devolución y 2 movimientos
        final movs = lotePuntos!['movimientos_puntos'] as List;
        expect(movs.map((m) => m['tipo_operacion']), ['PUNTOS_OTORGADOS', 'PUNTOS_RESTADOS']);
        expect(movs.first, containsPair('venta_uuid', venta));
        expect(movs.first, containsPair('cliente_id', _cliente));
        expect((await (await appDb.database)!.query(Schema.tablaMovimientosPuntos)).map((m) => m['estado_sync']), everyElement('sincronizado'));
        expect(await cola.obtenerOperacionesPendientes(), isEmpty);
      });

      test('si la venta no se pudo enviar, sus puntos esperan', () async {
        await vender();
        final r = await servicio(enviar: (lote) async {
          if (lote.containsKey('operaciones')) throw Exception('timeout');
          fail('los puntos no deben enviarse antes que su venta');
        }).sincronizarPendientes();
        expect(r.fallidas, 1);
        expect((await cola.obtenerOperacionesPendientes()).where((p) => p['tipo_operacion'] == 'PUNTOS_OTORGADOS'), hasLength(1));

        final r2 = await servicio(enviar: (l) async => ok(l)).sincronizarPendientes();
        expect(r2.sincronizadas, 2);
      });

      test('si el servidor rechaza la venta, los puntos se anulan y no se envían', () async {
        await vender();
        final enviados = <String>[];

        final r = await servicio(enviar: (lote) async {
          enviados.addAll(lote.keys.where((k) => k != 'enviado_en'));
          return {
            'resultados': [
              for (final o in (lote['operaciones'] as List? ?? const [])) {'uuid': o['uuid'], 'status': 'conflict', 'message': 'Stock insuficiente'},
            ],
          };
        }).sincronizarPendientes();

        expect(r.rechazadas, 1);
        expect(enviados, ['operaciones']); // nada de puntos
        expect(await puntos.obtenerSaldo(_cliente), 0);
      });

      test('si el servidor rechaza un movimiento de puntos, se deshace en el saldo', () async {
        await vender();
        await servicio(enviar: (lote) async {
          if (lote.containsKey('movimientos_puntos')) {
            return {
              'resultados': [
                for (final o in (lote['movimientos_puntos'] as List)) {'uuid': o['uuid'], 'status': 'conflict', 'message': 'Cliente inexistente'},
              ],
            };
          }
          return ok(lote);
        }).sincronizarPendientes();

        expect(await puntos.obtenerSaldo(_cliente), 0);
        final q = (await (await appDb.database)!.query(Schema.tablaSyncQueue, where: "tipo_operacion = 'PUNTOS_OTORGADOS'")).single;
        expect((q['estado'], q['ultimo_error']), ('rechazado', 'Cliente inexistente'));
      });

      test('con el servidor simulado los puntos siempre se aceptan', () async {
        await vender();
        final r = await servicio(sorteo: () => 0.9).sincronizarPendientes();
        expect(r.sincronizadas, 2);
      });
    });
  });

  // ===========================================================================
  group('migración v3 → v4', () {
    late String ruta;

    setUp(() => ruta = '${Directory.systemTemp.path}${Platform.pathSeparator}smartlook_mig4_${DateTime.now().microsecondsSinceEpoch}.db');

    tearDown(() async {
      for (final sufijo in ['', '-journal', '-wal', '-shm']) {
        final f = File('$ruta$sufijo');
        if (await f.exists()) await f.delete();
      }
    });

    test('conserva la cola (incluidas las devoluciones) y habilita puntos y avisos', () async {
      final v3 = await openDatabase(
        ruta,
        version: 3,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) async {
          for (final ddl in ddlV1) {
            await db.execute(ddl);
          }
          for (final s in [...Schema.migracionV2, ...Schema.migracionV3]) {
            await db.execute(s);
          }
        },
      );
      await v3.insert('turnos_caja', {'id': 't1', 'cajero_id': 7, 'sucursal_id': 1, 'monto_inicial_centavos': 0, 'fecha_apertura': '2026-10-01T08:00:00Z'});
      await v3.insert('operaciones_locales', {
        'uuid': 'v1', 'tipo_operacion': 'VENTA_CONTADO', 'sucursal_id': 1, 'cajero_id': 7, 'cliente_id': 55, 'total_centavos': 5000,
        'fecha': '2026-10-01T10:00:00Z', 'turno_uuid': 't1',
      });
      await v3.insert('devoluciones_locales', {
        'id': 'd1', 'venta_uuid': 'v1', 'tipo': 'DEVOLUCION', 'cajero_id': 7, 'sucursal_id': 1, 'total_devuelto_centavos': 1000, 'fecha': '2026-10-02T10:00:00Z', 'turno_uuid': 't1',
      });
      await v3.insert('sync_queue', {'id': 'q1', 'tipo_operacion': 'VENTA_CONTADO', 'operacion_uuid': 'v1', 'payload_json': '{}', 'intentos': 2, 'fecha_creacion': '2026-10-01T10:00:00Z'});
      await v3.insert('sync_queue', {'id': 'q2', 'tipo_operacion': 'DEVOLUCION', 'devolucion_id': 'd1', 'payload_json': '{}', 'fecha_creacion': '2026-10-02T10:00:00Z'});
      await v3.insert('sync_queue', {'id': 'q3', 'tipo_operacion': 'CIERRE_CAJA', 'turno_uuid': 't1', 'payload_json': '{}', 'fecha_creacion': '2026-10-03T10:00:00Z'});
      await v3.close();

      final db = await AppDatabase.abrir(ruta); // → onUpgrade(3, 4)
      final nuevo = AppDatabase.conBaseDeDatos(db);
      addTearDown(nuevo.cerrar);

      expect(
        (await db.query('sync_queue', orderBy: 'id')).map((q) => (q['id'], q['tipo_operacion'], q['operacion_uuid'], q['devolucion_id'], q['turno_uuid'], q['intentos'])),
        [('q1', 'VENTA_CONTADO', 'v1', null, null, 2), ('q2', 'DEVOLUCION', null, 'd1', null, 0), ('q3', 'CIERRE_CAJA', null, null, 't1', 0)],
      );
      expect(Sqflite.firstIntValue(await db.rawQuery('PRAGMA foreign_keys')), 1);

      // lo nuevo funciona sobre la base migrada
      expect(await PuntosDao(appDatabase: nuevo).otorgarPuntos(55, 'v1', 5000), 5);
      expect(Sqflite.firstIntValue(await db.rawQuery("SELECT COUNT(*) FROM sync_queue WHERE tipo_operacion = 'PUNTOS_OTORGADOS'")), 1);
      expect((await SuscripcionStockDao(appDatabase: nuevo).crearSuscripcion(clienteId: 55, productoId: 1, descripcion: 'x')).creada, isTrue);
    });

    test('v1 → v4 de una sola vez deja la misma estructura que una base nueva', () async {
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
      for (final tabla in [
        'operaciones_locales', 'sync_queue', 'turnos_caja', 'devoluciones_locales', 'devoluciones_locales_items',
        'puntos_cliente', 'movimientos_puntos', 'suscripciones_stock', 'catalogo_local',
      ]) {
        expect(await columnas(migrada, tabla), await columnas(fresca, tabla), reason: tabla);
      }
      final indices = await migrada.rawQuery("SELECT name FROM sqlite_master WHERE type = 'index'");
      expect(indices.map((i) => i['name']), containsAll(['ux_suscripcion_pendiente', 'ix_movimientos_puntos_venta', 'ix_sync_cola']));
    });
  });
}
