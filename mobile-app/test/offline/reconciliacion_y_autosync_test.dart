import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlook_mobile/core/database/app_database.dart';
import 'package:smartlook_mobile/core/database/schema.dart';
import 'package:smartlook_mobile/features/offline/data/catalogo_local_dao.dart';
import 'package:smartlook_mobile/features/offline/data/sync_queue_dao.dart';
import 'package:smartlook_mobile/features/offline/providers/conectividad_provider.dart';
import 'package:smartlook_mobile/features/offline/providers/venta_offline_provider.dart';
import 'package:smartlook_mobile/features/offline/services/sync_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'servidor_simulado.dart';

const _sinRed = [ConnectivityResult.none];
const _wifi = [ConnectivityResult.wifi];
const _datos = [ConnectivityResult.mobile];

Future<void> _esperar(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  late AppDatabase appDb;
  late SyncQueueDao cola;
  late CatalogoLocalDao catalogo;
  late VentaOfflineProvider pos;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    appDb = AppDatabase.conBaseDeDatos(await AppDatabase.abrir(inMemoryDatabasePath));
    cola = SyncQueueDao(appDatabase: appDb);
    catalogo = CatalogoLocalDao(appDatabase: appDb);
    pos = VentaOfflineProvider(catalogoDao: catalogo, colaDao: cola);
    await pos.cargarDatosMock(1);
  });

  tearDown(() => appDb.cerrar());

  Future<int> stock(int productoId) async => (await catalogo.obtenerProductos())
      .firstWhere((p) => p['producto_id'] == productoId)['cantidad_disponible'] as int;

  Future<String> uuidDeLaUltimaOperacion() async =>
      ((await (await appDb.database)!.query(Schema.tablaOperaciones, orderBy: 'rowid DESC', limit: 1)).single['uuid']) as String;

  /// Vende `cantidad` unidades del producto [productoId] por el POS (descuenta stock local).
  Future<String> vender(int productoId, int cantidad) async {
    final item = pos.productos.firstWhere((p) => p.productoId == productoId);
    for (var i = 0; i < cantidad; i++) {
      pos.agregarProducto(item);
    }
    expect(await pos.procesarVenta(cajeroId: 7, sucursalId: 1), isTrue);
    return uuidDeLaUltimaOperacion();
  }

  group('devolución de stock al rechazar (CU13)', () {
    test('un conflict devuelve a catalogo_local lo que la venta había descontado', () async {
      final antesCamiseta = await stock(101);
      final antesJean = await stock(103);
      final item1 = pos.productos.firstWhere((p) => p.productoId == 101);
      final item2 = pos.productos.firstWhere((p) => p.productoId == 103);
      pos
        ..agregarProducto(item1)
        ..agregarProducto(item1)
        ..agregarProducto(item2);
      expect(await pos.procesarVenta(cajeroId: 7, sucursalId: 1), isTrue);
      expect(await stock(101), antesCamiseta - 2);
      expect(await stock(103), antesJean - 1);

      final r = await SyncService(
        colaDao: cola,
        hayRed: () async => true,
        enviar: servidorSimulado(sorteo: () => 0.0), // conflict
      ).sincronizarPendientes();

      expect(r.rechazadas, 1);
      expect(await stock(101), antesCamiseta);
      expect(await stock(103), antesJean);
      final cab = (await (await appDb.database)!.query(Schema.tablaOperaciones)).single;
      expect(cab['estado'], 'rechazada');
    });

    test('una operación aceptada (ok) NO devuelve stock', () async {
      final antes = await stock(101);
      await vender(101, 2);

      await SyncService(colaDao: cola, hayRed: () async => true, enviar: servidorSimulado(sorteo: () => 0.9)).sincronizarPendientes();

      expect(await stock(101), antes - 2);
    });

    test('una reserva rechazada también devuelve su stock', () async {
      final antes = await stock(110);
      final item = pos.productos.firstWhere((p) => p.productoId == 110);
      await cola.guardarOperacionOffline({
        'sucursal_id': 1,
        'items': [
          {
            'inventario_id': item.inventarioId,
            'producto_id': 110,
            'talla_id': item.tallaId,
            'color_id': item.colorId,
            'nombre_producto': item.nombre,
            'cantidad': 1,
            'precio_unitario_centavos': item.precioCentavos,
          },
        ],
      }, 'res-1', Schema.tipoReservaCliente, 55, descontarStockLocal: true);
      expect(await stock(110), antes - 1);

      expect(await cola.marcarRechazada('res-1', 'Stock insuficiente'), 1);
      expect(await stock(110), antes);
    });

    test('una operación que no descontó stock no suma nada al rechazarse', () async {
      final antes = await stock(101);
      await cola.guardarOperacionOffline({
        'sucursal_id': 1,
        'cajero_id': 7,
        'items': [
          {'producto_id': 101, 'talla_id': 2, 'color_id': 1, 'nombre_producto': 'x', 'cantidad': 3, 'precio_unitario_centavos': 1},
        ],
      }, 'sin-descuento', Schema.tipoVentaContado, null); // descontarStockLocal: false

      expect(await cola.marcarRechazada('sin-descuento', 'x'), 0);
      expect(await stock(101), antes);
    });

    test('si el catálogo se refrescó desde el servidor después de la venta, no se infla el stock', () async {
      await vender(101, 2);
      await _esperar(5);
      await pos.cargarDatosMock(1); // catálogo "nuevo del servidor": vuelve a 25 y es posterior a la venta
      expect(await stock(101), 25);

      final uuid = await uuidDeLaUltimaOperacion();
      expect(await cola.marcarRechazada(uuid, 'Stock insuficiente'), 0);
      expect(await stock(101), 25);
    });

    test('no se devuelve dos veces: rechazar una operación ya rechazada falla sin tocar el stock', () async {
      final antes = await stock(101);
      final uuid = await vender(101, 2);
      await cola.marcarRechazada(uuid, 'x');
      expect(await stock(101), antes);

      await expectLater(cola.marcarRechazada(uuid, 'otra vez'), throwsStateError);
      expect(await stock(101), antes);
    });

    test('el rechazo es atómico: si falla, no queda la operación cerrada ni el stock sumado', () async {
      final antes = await stock(101);
      final uuid = await vender(101, 1);
      final db = (await appDb.database)!;
      // se corrompe el ítem para que devolver el stock reviente a mitad de la transacción
      await db.execute('DROP TABLE catalogo_local');

      await expectLater(cola.marcarRechazada(uuid, 'x'), throwsA(anything));

      final cola1 = await db.query(Schema.tablaSyncQueue);
      expect(cola1.single['estado'], 'pendiente');
      expect((await db.query(Schema.tablaOperaciones)).single['estado'], 'pendiente_sync');
      expect(antes, greaterThan(0));
    });
  });

  group('sincronización automática al volver la red', () {
    late StreamController<List<ConnectivityResult>> red;
    late int envios;
    var redActiva = false;

    /// Simula un cambio de red: también cambia lo que verá `hayRed` cuando el servicio sincronice.
    void emitir(List<ConnectivityResult> estado) {
      redActiva = estado.any((r) => r != ConnectivityResult.none);
      red.add(estado);
    }

    setUp(() async {
      redActiva = false;
      red = StreamController<List<ConnectivityResult>>.broadcast();
      envios = 0;
      await vender(101, 1); // hay algo pendiente
    });

    tearDown(() => red.close());

    SyncService crear({bool alIniciar = false, int espera = 40, int intervalo = 0, bool hayRed = false}) {
      redActiva = hayRed;
      return SyncService(
        colaDao: cola,
        hayRed: () async => redActiva,
        cambiosDeRed: red.stream,
        esperaTrasReconexion: Duration(milliseconds: espera),
        intervaloMinimoAuto: Duration(milliseconds: intervalo),
        sincronizarAlIniciar: alIniciar,
        enviar: (lote) async {
          envios++;
          return {
            'resultados': [
              for (final op in lote['operaciones'] as List) {'uuid': op['uuid'], 'status': 'ok', 'id_servidor': 1000 + envios},
            ],
          };
        },
      );
    }

    test('de sin red a wifi sincroniza una vez, automáticamente, y avisa el resultado', () async {
      final sync = crear();
      final avisos = <ResultadoSync>[];
      sync.alSincronizarAutomaticamente.listen(avisos.add);
      await sync.iniciarEscucha();

      emitir(_sinRed);
      emitir(_wifi);
      await _esperar(150);

      expect(envios, 1);
      expect(avisos.single.sincronizadas, 1);
      await sync.dispose();
    });

    test('de sin red a datos móviles también sincroniza', () async {
      final sync = crear();
      await sync.iniciarEscucha();
      emitir(_datos);
      await _esperar(150);
      expect(envios, 1);
      await sync.dispose();
    });

    test('un wifi que parpadea no dispara ráfagas: una sola sincronización', () async {
      await vender(103, 1);
      final sync = crear(espera: 80);
      await sync.iniciarEscucha();

      for (var i = 0; i < 5; i++) {
        emitir(_sinRed);
        await _esperar(10);
        emitir(_wifi);
        await _esperar(10);
      }
      await _esperar(250);

      expect(envios, 1);
      await sync.dispose();
    });

    test('si la red se cae antes de cumplirse la espera, no se sincroniza', () async {
      final sync = crear(espera: 80);
      await sync.iniciarEscucha();
      emitir(_wifi);
      await _esperar(20);
      emitir(_sinRed);
      await _esperar(200);

      expect(envios, 0);
      await sync.dispose();
    });

    test('cambiar de wifi a datos (siempre con red) no dispara nada', () async {
      final sync = crear(hayRed: true);
      await sync.iniciarEscucha();
      emitir(_wifi);
      await _esperar(100); // el estado inicial ya era "con red": no hay transición
      emitir(_datos);
      await _esperar(150);

      expect(envios, 0);
      await sync.dispose();
    });

    test('respeta el intervalo mínimo entre sincronizaciones automáticas', () async {
      await vender(103, 1);
      final sync = crear(espera: 10, intervalo: 300);
      await sync.iniciarEscucha();

      emitir(_wifi);
      await _esperar(100);
      expect(envios, 1);

      await vender(109, 1);
      emitir(_sinRed);
      emitir(_wifi);
      await _esperar(100);
      expect(envios, 1); // aún dentro del intervalo mínimo
      await _esperar(350);
      expect(envios, 2); // se reprogramó para cuando se cumple el intervalo
      await sync.dispose();
    });

    test('al arrancar con red sincroniza lo que quedó pendiente', () async {
      final sync = crear(alIniciar: true, hayRed: true, espera: 20);
      await sync.iniciarEscucha();
      await _esperar(120);
      expect(envios, 1);
      await sync.dispose();
    });

    test('dispose cancela la suscripción: los cambios de red posteriores no hacen nada', () async {
      final sync = crear(espera: 20);
      await sync.iniciarEscucha();
      await sync.dispose();

      emitir(_wifi);
      await _esperar(120);
      expect(envios, 0);
      expect(red.hasListener, isFalse);
    });

    test('dispose con una espera en curso cancela el temporizador', () async {
      final sync = crear(espera: 100);
      await sync.iniciarEscucha();
      emitir(_wifi);
      await sync.dispose();
      await _esperar(250);
      expect(envios, 0);
    });
  });

  group('ConectividadProvider (banner offline)', () {
    test('refleja la red y avisa solo cuando cambia', () async {
      final cambios = StreamController<List<ConnectivityResult>>.broadcast();
      final p = ConectividadProvider(cambios: cambios.stream, consultar: () async => _wifi);
      var notificaciones = 0;
      p.addListener(() => notificaciones++);
      await _esperar(20);
      expect(p.online, isTrue);

      cambios.add(_sinRed);
      await _esperar(20);
      expect(p.online, isFalse);
      expect(notificaciones, 1);

      cambios.add(_sinRed); // mismo estado: no notifica
      await _esperar(20);
      expect(notificaciones, 1);

      cambios.add(_datos);
      await _esperar(20);
      expect(p.online, isTrue);
      expect(notificaciones, 2);

      p.dispose();
      expect(cambios.hasListener, isFalse);
      await cambios.close();
    });

    test('si arranca sin red, lo detecta', () async {
      final cambios = StreamController<List<ConnectivityResult>>.broadcast();
      final p = ConectividadProvider(cambios: cambios.stream, consultar: () async => _sinRed);
      await _esperar(20);
      expect(p.online, isFalse);
      p.dispose();
      await cambios.close();
    });
  });
}
