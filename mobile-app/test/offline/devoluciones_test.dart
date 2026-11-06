import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartlook_mobile/core/database/app_database.dart';
import 'package:smartlook_mobile/core/database/schema.dart';
import 'package:smartlook_mobile/features/offline/data/catalogo_local_dao.dart';
import 'package:smartlook_mobile/features/offline/data/devolucion_dao.dart';
import 'package:smartlook_mobile/features/offline/data/sync_queue_dao.dart';
import 'package:smartlook_mobile/features/offline/data/turno_caja_dao.dart';
import 'package:smartlook_mobile/features/offline/providers/devolucion_provider.dart';
import 'package:smartlook_mobile/features/offline/providers/venta_offline_provider.dart';
import 'package:smartlook_mobile/features/offline/services/sync_service.dart';
import 'package:sqflite/sqflite.dart' show Sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'schema_v1_fixture.dart';
import 'servidor_simulado.dart';

// Catálogo mock (sucursal 1): 101 camiseta $19.99 (25) · 103 jean $59.99 (9) · 107 falda $39.99 (0)
//                             109 short $24.99 (30)    · 110 abrigo $129.99 (2)
const _camiseta = 101, _jean = 103, _falda = 107, _short = 109, _abrigo = 110;

void main() {
  late AppDatabase appDb;
  late SyncQueueDao cola;
  late TurnoCajaDao turnos;
  late DevolucionDao dao;
  late CatalogoLocalDao catalogo;
  late VentaOfflineProvider pos;
  late String turno;
  late String venta; // 2 camisetas + 1 jean = $99.97, hecha por el POS dentro del turno

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    appDb = AppDatabase.conBaseDeDatos(await AppDatabase.abrir(inMemoryDatabasePath));
    cola = SyncQueueDao(appDatabase: appDb);
    turnos = TurnoCajaDao(appDatabase: appDb);
    dao = DevolucionDao(appDatabase: appDb);
    catalogo = CatalogoLocalDao(appDatabase: appDb);
    pos = VentaOfflineProvider(catalogoDao: catalogo, colaDao: cola);
    await pos.cargarDatosMock(1);
    turno = await turnos.abrirTurno(7, 1, 10000); // $100.00 de caja inicial
    final camiseta = pos.productos.firstWhere((p) => p.productoId == _camiseta);
    final jean = pos.productos.firstWhere((p) => p.productoId == _jean);
    pos
      ..agregarProducto(camiseta)
      ..agregarProducto(camiseta)
      ..agregarProducto(jean);
    expect(await pos.procesarVenta(cajeroId: 7, sucursalId: 1, turnoUuid: turno), isTrue);
    venta = (await (await appDb.database)!.query(Schema.tablaOperaciones, columns: ['uuid'])).single['uuid'] as String;
  });

  tearDown(() => appDb.cerrar());

  Future<int> stock(int productoId) async => (await catalogo.obtenerProductos())
      .firstWhere((p) => p['producto_id'] == productoId)['cantidad_disponible'] as int;

  Future<int> contar(String tabla, [String? donde]) async {
    final db = (await appDb.database)!;
    return Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM $tabla ${donde ?? ''}'))!;
  }

  Map<String, dynamic> item(int productoId, int cantidad) {
    // talla y color del mock: 101 → (2,1), 103 → (4,3), 109 → (2,5), 110 → (3,6), 107 → (1,5)
    const variantes = {101: (2, 1), 103: (4, 3), 107: (1, 5), 109: (2, 5), 110: (3, 6)};
    final v = variantes[productoId]!;
    return {'producto_id': productoId, 'talla_id': v.$1, 'color_id': v.$2, 'cantidad': cantidad};
  }

  Future<ResultadoDevolucion> registrar(String tipo, List<Map<String, dynamic>> devueltos, List<Map<String, dynamic>> nuevos,
          {String? ventaUuid, String? turnoUuid, String? motivo}) =>
      dao.registrarDevolucion(ventaUuid ?? venta, tipo, devueltos, nuevos, turnoUuid ?? turno, motivo: motivo);

  // ---------------------------------------------------------------------------
  group('registro de cambios y devoluciones', () {
    test('devolución sin cambio: reembolsa a precio original y suma el stock', () async {
      final antes = await stock(_camiseta); // 25 - 2 vendidas = 23
      expect(antes, 23);

      final r = await registrar('DEVOLUCION', [item(_camiseta, 1)], [], motivo: 'No le quedó');

      expect((r.totalDevueltoCentavos, r.totalNuevoCentavos, r.diferenciaCentavos), (1999, 0, -1999));
      expect(await stock(_camiseta), antes + 1);

      final db = (await appDb.database)!;
      final d = (await db.query(Schema.tablaDevoluciones)).single;
      expect(d['tipo'], 'DEVOLUCION');
      expect(d['estado'], 'pendiente_sync');
      expect(d['motivo'], 'No le quedó');
      expect(d['venta_uuid'], venta);
      expect(d['turno_uuid'], turno);
      expect(d['cajero_id'], 7);
      final items = await db.query(Schema.tablaDevolucionesItems);
      expect(items.single['tipo_item'], 'DEVUELTO');
      expect(items.single['precio_centavos'], 1999);

      final q = (await db.query(Schema.tablaSyncQueue, where: "tipo_operacion = 'DEVOLUCION'")).single;
      expect(q['estado'], 'pendiente');
      expect(q['devolucion_id'], d['id']);
      expect(q['operacion_uuid'], isNull);
    });

    test('cambio con diferencia a favor del cliente: se le devuelve dinero', () async {
      final jeanAntes = await stock(_jean);
      final camisetaAntes = await stock(_camiseta);

      // devuelve un jean ($59.99) y se lleva una camiseta ($19.99)
      final r = await registrar('CAMBIO', [item(_jean, 1)], [item(_camiseta, 1)]);

      expect((r.totalDevueltoCentavos, r.totalNuevoCentavos), (5999, 1999));
      expect(r.diferenciaCentavos, -4000); // negativa: la tienda devuelve $40.00
      expect(await stock(_jean), jeanAntes + 1);
      expect(await stock(_camiseta), camisetaAntes - 1);
      // caja: 100.00 + 99.97 de la venta - 40.00 devueltos
      expect(await turnos.calcularMontoEsperado(turno), 10000 + 9997 - 4000);
      expect(await turnos.calcularMovimientoDevoluciones(turno), -4000);
    });

    test('cambio con diferencia a favor de la tienda: el cliente paga', () async {
      final abrigoAntes = await stock(_abrigo);
      final camisetaAntes = await stock(_camiseta);

      // devuelve una camiseta ($19.99) y se lleva un abrigo ($129.99)
      final r = await registrar('CAMBIO', [item(_camiseta, 1)], [item(_abrigo, 1)]);

      expect(r.diferenciaCentavos, 12999 - 1999); // el cliente paga $110.00
      expect(await stock(_abrigo), abrigoAntes - 1);
      expect(await stock(_camiseta), camisetaAntes + 1);
      expect(await turnos.calcularMontoEsperado(turno), 10000 + 9997 + 11000);
      final items = await (await appDb.database)!.query(Schema.tablaDevolucionesItems, orderBy: 'id');
      expect(items.map((i) => i['tipo_item']), ['DEVUELTO', 'NUEVO']);
    });

    test('el reembolso usa el precio de la venta original aunque el catálogo haya cambiado', () async {
      final db = (await appDb.database)!;
      await db.update(Schema.tablaCatalogoLocal, {'precio_centavos': 3000}, where: 'producto_id = ?', whereArgs: [_camiseta]);

      final r = await registrar('DEVOLUCION', [item(_camiseta, 2)], []);

      expect(r.totalDevueltoCentavos, 2 * 1999); // no 2 * 3000
    });

    test('varias líneas y una misma prenda repetida se agrupan', () async {
      final r = await registrar('DEVOLUCION', [item(_camiseta, 1), item(_camiseta, 1), item(_jean, 1)], []);
      expect(r.totalDevueltoCentavos, 2 * 1999 + 5999);
      expect(await contar(Schema.tablaDevolucionesItems), 2);
    });
  });

  group('validaciones (no se guarda nada)', () {
    Future<void> sinCambios(Future<void> Function() accion, Matcher error) async {
      final camiseta = await stock(_camiseta);
      final jean = await stock(_jean);
      final abrigo = await stock(_abrigo);
      await expectLater(accion(), error);
      expect(await contar(Schema.tablaDevoluciones), 0);
      expect(await contar(Schema.tablaDevolucionesItems), 0);
      expect(await contar(Schema.tablaSyncQueue, "WHERE tipo_operacion = 'DEVOLUCION'"), 0);
      expect((await stock(_camiseta), await stock(_jean), await stock(_abrigo)), (camiseta, jean, abrigo));
    }

    test('la venta debe existir', () async {
      await sinCambios(() => registrar('DEVOLUCION', [item(_camiseta, 1)], [], ventaUuid: 'no-existe'), throwsA(isA<VentaNoDevolvible>()));
    });

    test('sin turno abierto no se registra (inexistente o cerrado)', () async {
      await sinCambios(() => registrar('DEVOLUCION', [item(_camiseta, 1)], [], turnoUuid: 'no-existe'), throwsA(isA<TurnoNoAbierto>()));
      await turnos.cerrarTurno(turno, 0, confirmarPendientes: true);
      await sinCambios(() => registrar('DEVOLUCION', [item(_camiseta, 1)], []), throwsA(isA<TurnoNoAbierto>()));
    });

    test('no se pueden devolver más unidades de las vendidas, ni acumulando devoluciones', () async {
      await sinCambios(() => registrar('DEVOLUCION', [item(_camiseta, 3)], []), throwsA(isA<CantidadDevolucionExcedida>().having((e) => e.maximo, 'maximo', 2)));

      await registrar('DEVOLUCION', [item(_camiseta, 1)], []);
      await expectLater(
        registrar('DEVOLUCION', [item(_camiseta, 2)], []),
        throwsA(isA<CantidadDevolucionExcedida>().having((e) => e.maximo, 'maximo', 1)),
      );
      await registrar('DEVOLUCION', [item(_camiseta, 1)], []); // la que queda sí
      await expectLater(registrar('DEVOLUCION', [item(_camiseta, 1)], []), throwsA(isA<CantidadDevolucionExcedida>()));
    });

    test('una prenda que no era de la venta no se puede devolver', () async {
      await sinCambios(() => registrar('DEVOLUCION', [item(_abrigo, 1)], []), throwsA(isA<VentaNoDevolvible>()));
    });

    test('forma inválida: tipo, DEVOLUCION con prendas nuevas, CAMBIO sin ellas, cantidades', () async {
      await sinCambios(() => registrar('OTRO', [item(_camiseta, 1)], []), throwsArgumentError);
      await sinCambios(() => registrar('DEVOLUCION', [item(_camiseta, 1)], [item(_short, 1)]), throwsArgumentError);
      await sinCambios(() => registrar('CAMBIO', [item(_camiseta, 1)], []), throwsArgumentError);
      await sinCambios(() => registrar('DEVOLUCION', [], []), throwsArgumentError);
      await sinCambios(() => registrar('DEVOLUCION', [item(_camiseta, 0)], []), throwsArgumentError);
    });

    test('fuera del plazo de 7 días no se admite; dentro del plazo sí', () async {
      final vieja = DateTime.now().toUtc().subtract(const Duration(days: 10)).toIso8601String();
      final reciente = DateTime.now().toUtc().subtract(const Duration(days: 6)).toIso8601String();
      Future<void> venderConFecha(String uuid, String fecha) => cola.guardarOperacionOffline({
            'sucursal_id': 1, 'cajero_id': 7, 'fecha': fecha,
            'items': [{'producto_id': _camiseta, 'talla_id': 2, 'color_id': 1, 'nombre_producto': 'Camiseta', 'cantidad': 1, 'precio_unitario_centavos': 1999}],
          }, uuid, Schema.tipoVentaContado, null, turnoUuid: turno);
      await venderConFecha('vieja', vieja);
      await venderConFecha('reciente', reciente);

      await sinCambios(() => registrar('DEVOLUCION', [item(_camiseta, 1)], [], ventaUuid: 'vieja'), throwsA(isA<VentaNoDevolvible>()));
      await registrar('DEVOLUCION', [item(_camiseta, 1)], [], ventaUuid: 'reciente');
    });

    test('una venta rechazada o de otra sucursal, o una reserva, no admite devoluciones', () async {
      await cola.marcarRechazada(venta, 'Stock insuficiente');
      await sinCambios(() => registrar('DEVOLUCION', [item(_camiseta, 1)], []), throwsA(isA<VentaNoDevolvible>()));

      await cola.guardarOperacionOffline({'sucursal_id': 1, 'items': [{'producto_id': _camiseta, 'talla_id': 2, 'color_id': 1, 'nombre_producto': 'x', 'cantidad': 1, 'precio_unitario_centavos': 1}]},
          'reserva', Schema.tipoReservaCliente, 5);
      await sinCambios(() => registrar('DEVOLUCION', [item(_camiseta, 1)], [], ventaUuid: 'reserva'), throwsA(isA<VentaNoDevolvible>()));

      final otraTurno = await turnos.abrirTurno(8, 2, 0); // turno de otra sucursal
      await sinCambios(() => registrar('DEVOLUCION', [item(_camiseta, 1)], [], turnoUuid: otraTurno), throwsA(isA<VentaNoDevolvible>()));
    });
  });

  group('atomicidad del stock', () {
    test('si la prenda nueva no tiene stock se revierte todo, incluido el stock de lo devuelto', () async {
      final camiseta = await stock(_camiseta);
      final jean = await stock(_jean);

      await expectLater(registrar('CAMBIO', [item(_jean, 1)], [item(_falda, 1)]), throwsA(isA<StockLocalInsuficiente>())); // falda: stock 0
      expect(await stock(_jean), jean);
      expect(await stock(_camiseta), camiseta);
      expect(await contar(Schema.tablaDevoluciones), 0);

      // más de lo que hay (abrigo tiene 2)
      await expectLater(registrar('CAMBIO', [item(_jean, 1)], [item(_abrigo, 3)]), throwsA(isA<StockLocalInsuficiente>()));
      expect(await stock(_jean), jean);
    });

    test('una prenda nueva que no está en el catálogo local falla sin dejar rastro', () async {
      await expectLater(
        registrar('CAMBIO', [item(_jean, 1)], [{'producto_id': 999, 'talla_id': null, 'color_id': null, 'cantidad': 1}]),
        throwsA(isA<PrendaNoDisponible>()),
      );
      expect(await contar(Schema.tablaDevoluciones), 0);
    });

    test('cambiar una prenda por la misma funciona aunque el catálogo estuviera en 0', () async {
      final db = (await appDb.database)!;
      await db.update(Schema.tablaCatalogoLocal, {'cantidad_disponible': 0}, where: 'producto_id = ?', whereArgs: [_jean]);
      await registrar('CAMBIO', [item(_jean, 1)], [item(_jean, 1)]);
      expect(await stock(_jean), 0); // +1 -1
    });
  });

  group('arqueo de caja', () {
    test('una devolución sin sincronizar obliga a confirmar el cierre; el cierre lleva su efecto', () async {
      await cola.marcarSincronizada(venta, idServidor: 1); // la venta ya está en el servidor
      await registrar('DEVOLUCION', [item(_jean, 1)], []); // -$59.99 de la caja

      await expectLater(turnos.cerrarTurno(turno, 0), throwsA(isA<OperacionesPendientesEnTurno>().having((e) => e.cantidad, 'cantidad', 1)));

      final r = await turnos.cerrarTurno(turno, 10000 + 9997 - 5999, confirmarPendientes: true);
      expect(r.esperadoCentavos, 10000 + 9997 - 5999);
      expect(r.diferenciaCentavos, 0);
      final payload = (await cola.obtenerOperacionesPendientes()).last['payload_json'] as String;
      expect(payload, allOf(contains('"devoluciones_neto_centavos":-5999'), contains('"devoluciones":["')));
    });

    test('una devolución rechazada deja de contar y deshace el stock', () async {
      final camiseta = await stock(_camiseta);
      final jean = await stock(_jean);
      final abrigo = await stock(_abrigo);
      final r = await registrar('CAMBIO', [item(_jean, 1)], [item(_abrigo, 1)]);
      expect(await turnos.calcularMovimientoDevoluciones(turno), 12999 - 5999);

      await dao.marcarRechazada(r.id, 'Stock insuficiente');

      expect(await turnos.calcularMovimientoDevoluciones(turno), 0);
      expect((await stock(_jean), await stock(_abrigo), await stock(_camiseta)), (jean, abrigo, camiseta));
      final db = (await appDb.database)!;
      expect((await db.query(Schema.tablaDevoluciones)).single['estado'], 'rechazada');
      expect((await db.query(Schema.tablaSyncQueue, where: "tipo_operacion = 'DEVOLUCION'")).single['estado'], 'rechazado');
      // y lo devuelto otra vez se puede devolver
      await registrar('DEVOLUCION', [item(_jean, 1)], []);
    });

    test('no se rechaza dos veces (el stock no se deshace dos veces)', () async {
      final r = await registrar('DEVOLUCION', [item(_jean, 1)], []);
      await dao.marcarRechazada(r.id, 'x');
      final despues = await stock(_jean);
      await expectLater(dao.marcarRechazada(r.id, 'otra vez'), throwsStateError);
      expect(await stock(_jean), despues);
    });
  });

  group('sincronización de devoluciones', () {
    SyncService servicio({EnviarLote? enviar, double Function()? sorteo}) =>
        SyncService(colaDao: cola, turnoDao: turnos, devolucionDao: dao, hayRed: () async => true, enviar: enviar ?? servidorSimulado(sorteo: sorteo ?? () => 0.9));

    Map<String, dynamic> respuestaOk(Map<String, dynamic> lote) => {
          'resultados': [
            for (final clave in ['operaciones', 'devoluciones', 'cierres_caja'])
              for (final o in (lote[clave] as List? ?? const [])) {'uuid': o['uuid'], 'status': 'ok', 'id_servidor': 100},
          ],
        };

    test('la devolución viaja después de su venta original, y el cierre después de ambas', () async {
      final r = await registrar('CAMBIO', [item(_jean, 1)], [item(_short, 1)]);
      await turnos.cerrarTurno(turno, 0, confirmarPendientes: true);
      final claves = <String>[];

      final res = await servicio(
        enviar: (lote) async {
          claves.add(['operaciones', 'devoluciones', 'cierres_caja'].firstWhere(lote.containsKey));
          return respuestaOk(lote);
        },
      ).sincronizarPendientes();

      expect(claves, ['operaciones', 'devoluciones', 'cierres_caja']);
      expect(res.sincronizadas, 3);
      final d = (await (await appDb.database)!.query(Schema.tablaDevoluciones, where: 'id = ?', whereArgs: [r.id])).single;
      expect(d['estado'], 'sincronizada');
      expect(d['id_servidor'], 100);
      expect((await turnos.obtenerTurno(turno))!['estado'], 'sincronizado');
    });

    test('el lote de la devolución trae la venta original, los ítems y la diferencia', () async {
      await registrar('CAMBIO', [item(_jean, 1)], [item(_short, 1)], motivo: 'Talla');
      Map<String, dynamic>? lote;
      await servicio(enviar: (l) async {
        if (l.containsKey('devoluciones')) lote = l;
        return respuestaOk(l);
      }).sincronizarPendientes();

      final d = (lote!['devoluciones'] as List).single as Map;
      expect(d['venta_uuid'], venta);
      expect(d['tipo'], 'CAMBIO');
      expect(d['motivo'], 'Talla');
      expect(d['diferencia_centavos'], 2499 - 5999);
      expect((d['items_devueltos'] as List).single, containsPair('precio_centavos', 5999));
      expect((d['items_nuevos'] as List).single, containsPair('producto_id', _short));
    });

    test('si la venta original no se pudo enviar, la devolución (y el cierre) esperan', () async {
      await registrar('DEVOLUCION', [item(_jean, 1)], []);
      await turnos.cerrarTurno(turno, 0, confirmarPendientes: true);

      final r1 = await servicio(enviar: (lote) async {
        if (lote.containsKey('operaciones')) throw Exception('timeout');
        fail('no debe enviarse nada más mientras la venta siga pendiente');
      }).sincronizarPendientes();
      expect(r1.fallidas, 1);
      expect((await cola.obtenerOperacionesPendientes()).where((p) => p['tipo_operacion'] == 'DEVOLUCION'), hasLength(1));

      final r2 = await servicio(enviar: (l) async => respuestaOk(l)).sincronizarPendientes();
      expect(r2.sincronizadas, 3);
    });

    test('si el servidor responde "pendiente" a la devolución, sigue pendiente con su mensaje (no error ni rechazo)', () async {
      final r = await registrar('DEVOLUCION', [item(_jean, 1)], []);
      Map<String, dynamic> pendiente(Map<String, dynamic> lote) => {
            'resultados': [
              for (final o in (lote['operaciones'] as List? ?? const [])) {'uuid': o['uuid'], 'status': 'ok', 'id_servidor': 5},
              for (final x in (lote['devoluciones'] as List? ?? const []))
                {'uuid': x['uuid'], 'status': 'pendiente', 'message': 'Falta sincronizar la venta original'},
            ],
          };
      final antes = ((await (await appDb.database)!.query(Schema.tablaDevoluciones, where: 'id = ?', whereArgs: [r.id])).single)['estado'];

      final res = await servicio(enviar: (l) async => pendiente(l)).sincronizarPendientes();

      expect((res.sincronizadas, res.enEspera, res.fallidas, res.rechazadas), (1, 1, 0, 0)); // la venta sí; la devolución espera
      expect(res.resumen, contains('Falta sincronizar la venta original'));
      final fila = (await (await appDb.database)!.query(Schema.tablaSyncQueue, where: "tipo_operacion = 'DEVOLUCION'")).single;
      expect(fila['estado'], 'pendiente');
      expect(fila['intentos'], 1);
      expect(fila['ultimo_error'], 'Falta sincronizar la venta original');
      final d = (await (await appDb.database)!.query(Schema.tablaDevoluciones, where: 'id = ?', whereArgs: [r.id])).single;
      expect(d['estado'], antes, reason: 'la devolución no cambia de estado');

      final res2 = await servicio(enviar: (l) async => respuestaOk(l)).sincronizarPendientes();
      expect(res2.sincronizadas, 1);
      expect((await (await appDb.database)!.query(Schema.tablaDevoluciones, where: 'id = ?', whereArgs: [r.id])).single['estado'], 'sincronizada');
    });

    test('si el servidor rechaza la venta original, su devolución se rechaza y el stock queda como al inicio', () async {
      final camisetaInicial = await stock(_camiseta) + 2; // antes de la venta
      final jeanInicial = await stock(_jean) + 1;
      await registrar('DEVOLUCION', [item(_jean, 1)], []);

      final res = await servicio(enviar: (lote) async {
        return {
          'resultados': [
            for (final o in (lote['operaciones'] as List? ?? const [])) {'uuid': o['uuid'], 'status': 'conflict', 'message': 'Stock insuficiente'},
          ],
        };
      }).sincronizarPendientes();

      expect(res.rechazadas, 2); // la venta y la devolución
      expect(await stock(_camiseta), camisetaInicial);
      expect(await stock(_jean), jeanInicial);
      expect((await (await appDb.database)!.query(Schema.tablaDevoluciones)).single['estado'], 'rechazada');
      expect(await turnos.calcularMontoEsperado(turno), 10000); // ni venta ni devolución cuentan
    });

    test('si el servidor rechaza la devolución se deshace su stock y deja de afectar la caja', () async {
      await cola.marcarSincronizada(venta, idServidor: 1);
      final jean = await stock(_jean);
      final short = await stock(_short);
      await registrar('CAMBIO', [item(_jean, 1)], [item(_short, 1)]);

      final res = await servicio(sorteo: () => 0.0).sincronizarPendientes(); // simulador: conflict

      expect(res.rechazadas, 1);
      expect(await stock(_jean), jean);
      expect(await stock(_short), short);
      expect(await turnos.calcularMovimientoDevoluciones(turno), 0);
    });
  });

  group('DevolucionProvider (pantalla)', () {
    late DevolucionProvider provider;

    setUp(() => provider = DevolucionProvider(dao: dao, catalogoDao: catalogo));

    test('busca por número de recibo, arma un cambio y calcula la diferencia', () async {
      await provider.buscar(1);
      expect(provider.ventas, hasLength(1));

      final recibo = provider.ventas.single.recibo; // primeros 8 caracteres en mayúsculas
      await provider.buscar(1, texto: recibo.toLowerCase());
      expect(provider.ventas.single.uuid, venta);
      await provider.buscar(1, texto: 'zzzz');
      expect(provider.ventas, isEmpty);

      expect(await provider.seleccionarVenta(venta), isTrue);
      final jean = provider.venta!.items.firstWhere((i) => i.productoId == _jean);
      provider.cambiarDevolucion(jean, 1);
      provider.cambiarDevolucion(jean, 5); // no pasa del máximo
      expect(provider.cantidadADevolver(jean), 1);
      expect(provider.tipo, 'DEVOLUCION');
      expect(provider.diferenciaCentavos, -5999);

      await provider.cargarCatalogo(1);
      final abrigo = provider.catalogo.firstWhere((p) => p.productoId == _abrigo);
      expect(provider.agregarNuevo(abrigo), isTrue);
      expect(provider.tipo, 'CAMBIO');
      expect(provider.diferenciaCentavos, 12999 - 5999);

      final r = await provider.confirmar(turnoUuid: turno, motivo: 'Prefirió el abrigo');
      expect(r!.diferenciaCentavos, 7000);
      expect(provider.venta, isNull);
      expect(await stock(_abrigo), 1);
    });

    test('no deja confirmar sin prendas devueltas; sin caja abierta muestra el aviso', () async {
      await provider.seleccionarVenta(venta);
      expect(provider.puedeConfirmar, isFalse);
      provider.cambiarDevolucion(provider.venta!.items.first, 1);
      expect(provider.puedeConfirmar, isTrue);

      await turnos.cerrarTurno(turno, 0, confirmarPendientes: true);
      expect(await provider.confirmar(turnoUuid: turno), isNull);
      expect(provider.mensaje, contains('caja'));
      expect(provider.venta, isNotNull); // conserva lo armado
    });

    test('una venta fuera de plazo o ya devuelta por completo no se abre', () async {
      expect(await provider.seleccionarVenta('no-existe'), isFalse);
      await registrar('DEVOLUCION', [item(_camiseta, 2), item(_jean, 1)], []);
      expect(await provider.seleccionarVenta(venta), isFalse);
      expect(provider.mensaje, contains('ya fueron devueltas'));
    });
  });

  group('migración v2 → v3', () {
    late String ruta;

    setUp(() => ruta = '${Directory.systemTemp.path}${Platform.pathSeparator}smartlook_mig3_${DateTime.now().microsecondsSinceEpoch}.db');

    tearDown(() async {
      for (final sufijo in ['', '-journal', '-wal', '-shm']) {
        final f = File('$ruta$sufijo');
        if (await f.exists()) await f.delete();
      }
    });

    test('conserva turnos, ventas y cola de una base v2 y habilita devoluciones', () async {
      // base v2: esquema v1 + migración a v2 aplicada a mano, con datos
      final v2 = await openDatabase(
        ruta,
        version: 2,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) async {
          for (final ddl in ddlV1) {
            await db.execute(ddl);
          }
          for (final s in Schema.migracionV2) {
            await db.execute(s);
          }
        },
      );
      await v2.insert('turnos_caja', {'id': 't1', 'cajero_id': 7, 'sucursal_id': 1, 'monto_inicial_centavos': 500, 'fecha_apertura': '2026-10-01T08:00:00Z'});
      await v2.insert('operaciones_locales', {
        'uuid': 'v1', 'tipo_operacion': 'VENTA_CONTADO', 'sucursal_id': 1, 'cajero_id': 7, 'total_centavos': 900,
        'fecha': DateTime.now().toUtc().toIso8601String(), 'turno_uuid': 't1',
      });
      await v2.insert('operaciones_locales_items', {'operacion_uuid': 'v1', 'producto_id': 101, 'talla_id': 2, 'color_id': 1, 'nombre_producto': 'Camiseta', 'cantidad': 1, 'precio_unitario_centavos': 900});
      await v2.insert('sync_queue', {'id': 'q1', 'tipo_operacion': 'VENTA_CONTADO', 'operacion_uuid': 'v1', 'payload_json': '{}', 'estado': 'pendiente', 'intentos': 3, 'fecha_creacion': '2026-10-01T09:00:00Z'});
      await v2.insert('sync_queue', {'id': 'q2', 'tipo_operacion': 'CIERRE_CAJA', 'turno_uuid': 't1', 'payload_json': '{}', 'estado': 'pendiente', 'fecha_creacion': '2026-10-01T18:00:00Z'});
      await v2.close();

      final db = await AppDatabase.abrir(ruta); // → onUpgrade(2, 3)
      final nuevo = AppDatabase.conBaseDeDatos(db);
      addTearDown(nuevo.cerrar);

      expect((await db.query('sync_queue', orderBy: 'id')).map((q) => (q['id'], q['tipo_operacion'], q['turno_uuid'], q['intentos'])),
          [('q1', 'VENTA_CONTADO', null, 3), ('q2', 'CIERRE_CAJA', 't1', 0)]);
      expect(Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM turnos_caja')), 1);
      expect(Sqflite.firstIntValue(await db.rawQuery('PRAGMA foreign_keys')), 1);

      // lo nuevo funciona sobre la base migrada
      await db.insert('catalogo_local', {
        'inventario_id': 1, 'sucursal_id': 1, 'producto_id': 101, 'talla_id': 2, 'color_id': 1, 'nombre_producto': 'Camiseta',
        'precio_centavos': 900, 'cantidad_disponible': 5, 'sincronizado_en': '2026-10-01T00:00:00Z',
      });
      final r = await DevolucionDao(appDatabase: nuevo).registrarDevolucion(
        'v1', 'DEVOLUCION',
        [{'producto_id': 101, 'talla_id': 2, 'color_id': 1, 'cantidad': 1}], [], 't1',
      );
      expect(r.totalDevueltoCentavos, 900);
      expect(Sqflite.firstIntValue(await db.rawQuery("SELECT COUNT(*) FROM sync_queue WHERE tipo_operacion = 'DEVOLUCION'")), 1);
    });
  });
}
