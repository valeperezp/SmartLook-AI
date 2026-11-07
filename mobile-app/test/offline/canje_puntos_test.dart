import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartlook_mobile/core/config/regla_puntos.dart';
import 'package:smartlook_mobile/core/database/app_database.dart';
import 'package:smartlook_mobile/core/database/schema.dart';
import 'package:smartlook_mobile/core/services/fidelizacion_service.dart';
import 'package:smartlook_mobile/features/offline/data/catalogo_local_dao.dart';
import 'package:smartlook_mobile/features/offline/data/puntos_dao.dart';
import 'package:smartlook_mobile/features/offline/data/sync_queue_dao.dart';
import 'package:smartlook_mobile/features/offline/providers/venta_offline_provider.dart';
import 'package:smartlook_mobile/features/offline/services/saldo_puntos_cliente.dart';
import 'package:smartlook_mobile/features/offline/services/sync_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// CU17 — canje de puntos como descuento al vender (POS offline) y la regla "cuánto vale un punto" que viene del backend.
void main() {
  const cliente = 55;

  late AppDatabase appDb;
  late SyncQueueDao cola;
  late CatalogoLocalDao catalogo;
  late PuntosDao puntos;
  late VentaOfflineProvider pos;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ReglaPuntos.restablecer();
    appDb = AppDatabase.conBaseDeDatos(await AppDatabase.abrir(inMemoryDatabasePath));
    cola = SyncQueueDao(appDatabase: appDb);
    catalogo = CatalogoLocalDao(appDatabase: appDb);
    puntos = PuntosDao(appDatabase: appDb);
    pos = VentaOfflineProvider(catalogoDao: catalogo, colaDao: cola);
    await pos.cargarDatosMock(1);
  });

  tearDown(() async {
    ReglaPuntos.restablecer();
    await appDb.cerrar();
  });

  Future<int> stock(int productoId) async =>
      (await catalogo.obtenerProductos()).firstWhere((p) => p['producto_id'] == productoId)['cantidad_disponible'] as int;

  /// Vende 1 unidad del producto (101: 19.99 · 102: 29.99 · 103: 59.99 · 104: 74.99) y devuelve si se guardó.
  Future<bool> vender(int productoId, {int? clienteId = cliente, int puntosACanjear = 0, int? recibido}) async {
    pos.agregarProducto(pos.productos.firstWhere((p) => p.productoId == productoId));
    return pos.procesarVenta(cajeroId: 7, sucursalId: 1, clienteId: clienteId, puntosACanjear: puntosACanjear, montoRecibidoCentavos: recibido);
  }

  Future<Map<String, Object?>> ultimaVenta() async =>
      (await (await appDb.database)!.query(Schema.tablaOperaciones, orderBy: 'rowid DESC', limit: 1)).single;

  Future<List<Map<String, Object?>>> movimientos() async => (await appDb.database)!.query(Schema.tablaMovimientosPuntos, orderBy: 'rowid');

  group('regla de puntos (viene del backend)', () {
    test('por defecto 1000 centavos y se usa para ganar y para canjear', () {
      expect(ReglaPuntos.valorPuntoCentavos, 1000);
      expect(ReglaPuntos.puntosPara(2999), 2);
      expect(ReglaPuntos.descuentoCentavos(3), 3000);
    });

    test('cuando el backend dice otro valor, cambia todo (no está fijo en la app)', () {
      ReglaPuntos.establecer(250);

      expect(ReglaPuntos.puntosPara(1000), 4);
      expect(ReglaPuntos.descuentoCentavos(4), 1000);
    });

    test('puntosUsables: todos los que tiene sin pasarse del total', () {
      expect(ReglaPuntos.puntosUsables(saldo: 8, totalCentavos: 5999), 5); // el total solo admite 5 puntos de 10.00
      expect(ReglaPuntos.puntosUsables(saldo: 2, totalCentavos: 5999), 2); // solo tiene 2
      expect(ReglaPuntos.puntosUsables(saldo: 0, totalCentavos: 5999), 0);
      expect(ReglaPuntos.puntosUsables(saldo: 5, totalCentavos: 999), 0); // no alcanza ni para un punto
    });

    test('se guarda en el dispositivo y se recupera al arrancar (para usarla sin conexión)', () async {
      await ReglaPuntos.guardar(500);
      ReglaPuntos.restablecer();
      expect(ReglaPuntos.valorPuntoCentavos, 1000);

      await ReglaPuntos.cargarGuardada();

      expect(ReglaPuntos.valorPuntoCentavos, 500);
    });

    test('valores inválidos del servidor se ignoran', () async {
      await ReglaPuntos.guardar(0);
      ReglaPuntos.establecer(-5);

      expect(ReglaPuntos.valorPuntoCentavos, 1000);
    });

    test('cada respuesta del backend actualiza la regla guardada', () async {
      final servicio = FidelizacionService(
        obtener: (ruta) async => ruta.endsWith('/puntos') ? {'cliente_id': 55, 'saldo': 7, 'valor_punto_centavos': 2000} : {'valor_punto_centavos': 1500},
      );

      final p = await servicio.puntosDeCliente(55);
      expect((p.saldo, p.valorPuntoCentavos), (7, 2000));
      expect(ReglaPuntos.valorPuntoCentavos, 2000);

      expect(await servicio.sincronizarRegla(), 1500);
      expect(ReglaPuntos.valorPuntoCentavos, 1500);
    });
  });

  group('venta offline con canje', () {
    test('el total baja, los puntos se restan del saldo y los que gana se calculan sobre lo que de verdad pagó', () async {
      await puntos.reconciliarSaldo(cliente, 8);
      final antesStock = await stock(103);

      final ok = await vender(103, puntosACanjear: 3); // 59.99 - 30.00 = 29.99

      expect(ok, isTrue);
      expect((await ultimaVenta())['total_centavos'], 2999);
      expect(pos.puntosCanjeadosUltimaVenta, 3);
      expect(pos.puntosUltimaVenta, 2); // gana 2 por 29.99 (no por 59.99)
      expect(await puntos.obtenerSaldo(cliente), 8 - 3 + 2);
      expect(await stock(103), antesStock - 1);
    });

    test('el canje queda en la cola de sincronización como PUNTOS_RESTADOS (motivo canje) ligado a la venta', () async {
      await puntos.reconciliarSaldo(cliente, 8);
      await vender(103, puntosACanjear: 3);
      final venta = await ultimaVenta();

      final db = (await appDb.database)!;
      final canje = (await movimientos()).singleWhere((m) => m['tipo'] == 'canjeado');
      expect((canje['cantidad'], canje['operacion_uuid'], canje['venta_uuid'], canje['estado_sync']), (3, venta['uuid'], venta['uuid'], 'pendiente'));
      final entrada = (await db.query(Schema.tablaSyncQueue, where: "tipo_operacion = 'PUNTOS_RESTADOS'")).single;
      expect(entrada['estado'], 'pendiente');
      expect(entrada['payload_json'], allOf(contains('"motivo":"canje"'), contains('"cantidad":3')));
      final laVenta = (await db.query(Schema.tablaSyncQueue, where: "tipo_operacion = 'VENTA_CONTADO'")).single;
      expect(laVenta['payload_json'], contains('"puntos_canjeados":3'));
    });

    test('no se puede canjear más puntos de los que se tienen: no se guarda nada', () async {
      await puntos.reconciliarSaldo(cliente, 2);
      final antesStock = await stock(103);

      final ok = await vender(103, puntosACanjear: 3);

      expect(ok, isFalse);
      expect(pos.ultimoMensaje, contains('no tiene suficientes puntos'));
      expect((await (await appDb.database)!.query(Schema.tablaOperaciones)), isEmpty);
      expect(await puntos.obtenerSaldo(cliente), 2);
      expect(await stock(103), antesStock);
      expect(pos.lineas, isNotEmpty, reason: 'el carrito se conserva para corregir la venta');
    });

    test('el descuento no puede ser mayor al total de la compra', () async {
      await puntos.reconciliarSaldo(cliente, 99);

      final ok = await vender(101, puntosACanjear: 3); // 3 × 10.00 > 19.99

      expect(ok, isFalse);
      expect(pos.ultimoMensaje, contains('no puede ser mayor al total'));
      expect(await puntos.obtenerSaldo(cliente), 99);
    });

    test('canjear exige indicar el cliente', () async {
      final ok = await vender(103, clienteId: null, puntosACanjear: 2);

      expect(ok, isFalse);
      expect(pos.ultimoMensaje, contains('indicar el cliente'));
    });

    test('con la regla de la empresa en 500 centavos, 4 puntos descuentan 20.00 y se ganan puntos por 39.99', () async {
      ReglaPuntos.establecer(500);
      await puntos.reconciliarSaldo(cliente, 8);

      await vender(103, puntosACanjear: 4);

      expect((await ultimaVenta())['total_centavos'], 5999 - 2000);
      expect(pos.puntosUltimaVenta, 7); // 3999 ÷ 500
    });

    test('el monto recibido debe cubrir el total YA con el descuento', () async {
      await puntos.reconciliarSaldo(cliente, 8);

      expect(await vender(103, puntosACanjear: 3, recibido: 2000), isFalse); // 29.99 no se cubre con 20.00
      expect(pos.ultimoMensaje, contains('no cubre el total'));
      // el carrito se conserva: se vuelve a cobrar la MISMA venta con un monto que sí alcanza
      expect(await pos.procesarVenta(cajeroId: 7, sucursalId: 1, clienteId: cliente, puntosACanjear: 3, montoRecibidoCentavos: 3000), isTrue);
    });

    test('sin canje todo sigue igual que antes', () async {
      final ok = await vender(103);

      expect(ok, isTrue);
      expect((await ultimaVenta())['total_centavos'], 5999);
      expect(pos.puntosCanjeadosUltimaVenta, 0);
      expect((await movimientos()).map((m) => m['tipo']), ['ganado']);
    });
  });

  group('saldo disponible del cliente', () {
    test('reconciliarSaldo: saldo del servidor + lo pendiente de este dispositivo (ganado suma, canje resta)', () async {
      await puntos.reconciliarSaldo(cliente, 8);
      await vender(103, puntosACanjear: 3); // pendientes: canjeado 3, ganado 2

      final saldo = await puntos.reconciliarSaldo(cliente, 10); // el servidor aún dice 10

      expect(saldo, 10 - 3 + 2);
      expect(await puntos.obtenerSaldo(cliente), 9);
    });

    test('con red usa el saldo del servidor y adopta su regla', () async {
      final servicio = FidelizacionService(obtener: (_) async => {'cliente_id': 55, 'saldo': 12, 'valor_punto_centavos': 2000});

      final saldo = await SaldoPuntosCliente(servicio: servicio, dao: puntos).disponible(cliente);

      expect(saldo, 12);
      expect(ReglaPuntos.valorPuntoCentavos, 2000);
    });

    test('sin red usa el saldo guardado en el dispositivo', () async {
      await puntos.reconciliarSaldo(cliente, 6);
      final servicio = FidelizacionService(obtener: (_) async => throw Exception('sin red'));

      final saldo = await SaldoPuntosCliente(servicio: servicio, dao: puntos).disponible(cliente);

      expect(saldo, 6);
    });
  });

  group('sincronización del canje', () {
    /// Servidor falso que guarda los lotes que recibe y responde ok (o conflict para las operaciones si [rechazarVentas]).
    ({EnviarLote enviar, List<Map<String, dynamic>> lotes}) servidor({bool rechazarVentas = false}) {
      final lotes = <Map<String, dynamic>>[];
      var id = 500;
      Future<Map<String, dynamic>> enviar(Map<String, dynamic> lote) async {
        lotes.add(lote);
        return {
          'resultados': [
            for (final clave in const ['operaciones', 'movimientos_puntos', 'devoluciones', 'cierres_caja'])
              for (final x in (lote[clave] as List? ?? const []))
                if (clave == 'operaciones' && rechazarVentas)
                  {'uuid': (x as Map)['uuid'], 'status': 'conflict', 'message': 'Rechazada'}
                else
                  {'uuid': (x as Map)['uuid'], 'status': 'ok', 'id_servidor': id++},
          ],
        };
      }

      return (enviar: enviar, lotes: lotes);
    }

    test('la venta viaja con puntos_canjeados y luego el movimiento PUNTOS_RESTADOS con motivo "canje"', () async {
      await puntos.reconciliarSaldo(cliente, 8);
      await vender(103, puntosACanjear: 3);
      final uuid = (await ultimaVenta())['uuid'];
      final srv = servidor();

      final r = await SyncService(colaDao: cola, puntosDao: puntos, hayRed: () async => true, enviar: srv.enviar).sincronizarPendientes();

      expect((r.fallidas, r.rechazadas), (0, 0));
      final operaciones = srv.lotes.expand((l) => (l['operaciones'] as List? ?? const [])).cast<Map>().single;
      expect(operaciones['puntos_canjeados'], 3);
      expect(operaciones['total_centavos'], 2999);
      final movimientosEnviados = srv.lotes.expand((l) => (l['movimientos_puntos'] as List? ?? const [])).cast<Map>().toList();
      final canje = movimientosEnviados.singleWhere((m) => m['tipo_operacion'] == 'PUNTOS_RESTADOS');
      expect((canje['motivo'], canje['cantidad'], canje['operacion_uuid'], canje['venta_uuid']), ('canje', 3, uuid, uuid));
      expect(await puntos.obtenerSaldo(cliente), 7);
    });

    test('una venta sin canje no manda puntos_canjeados', () async {
      await vender(103);
      final srv = servidor();

      await SyncService(colaDao: cola, puntosDao: puntos, hayRed: () async => true, enviar: srv.enviar).sincronizarPendientes();

      expect(srv.lotes.expand((l) => (l['operaciones'] as List? ?? const [])).cast<Map>().single.containsKey('puntos_canjeados'), isFalse);
    });

    test('si el servidor rechaza la venta, los puntos canjeados vuelven al saldo', () async {
      await puntos.reconciliarSaldo(cliente, 8);
      await vender(103, puntosACanjear: 3);
      expect(await puntos.obtenerSaldo(cliente), 7);

      await SyncService(colaDao: cola, puntosDao: puntos, hayRed: () async => true, enviar: servidor(rechazarVentas: true).enviar).sincronizarPendientes();

      expect(await puntos.obtenerSaldo(cliente), 8, reason: 'canje devuelto y puntos ganados anulados');
      expect((await movimientos()).every((m) => m['estado_sync'] == 'rechazado'), isTrue);
    });
  });
}
