import 'package:flutter_test/flutter_test.dart';
import 'package:smartlook_mobile/core/database/app_database.dart';
import 'package:smartlook_mobile/core/database/schema.dart';
import 'package:smartlook_mobile/features/offline/data/catalogo_local_dao.dart';
import 'package:smartlook_mobile/features/offline/data/mock_data.dart';
import 'package:smartlook_mobile/features/offline/data/sync_queue_dao.dart';
import 'package:smartlook_mobile/features/offline/models/catalogo_item.dart';
import 'package:smartlook_mobile/features/offline/providers/catalogo_offline_provider.dart';
import 'package:smartlook_mobile/features/offline/providers/venta_offline_provider.dart';
import 'package:sqflite/sqflite.dart' show Sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Map<String, dynamic> _operacion({int? cajeroId = 7, List<Object?>? items}) => {
      'sucursal_id': 1,
      'cajero_id': cajeroId,
      'items': items ??
          [
            {
              'producto_id': 101,
              'talla_id': 2,
              'color_id': 1,
              'nombre_producto': 'Camiseta básica',
              'cantidad': 2,
              'precio_unitario_centavos': 1999,
            },
            {
              'producto_id': 103,
              'nombre_producto': 'Jean slim',
              'cantidad': 1,
              'precio_unitario_centavos': 5999,
            },
          ],
    };

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

  Future<int> contar(String tabla) async {
    final db = (await appDb.database)!;
    return Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM $tabla'))!;
  }

  test('las claves foráneas están activadas', () async {
    final db = (await appDb.database)!;
    expect(Sqflite.firstIntValue(await db.rawQuery('PRAGMA foreign_keys')), 1);
    await expectLater(
      db.insert(Schema.tablaOperacionesItems, {
        'operacion_uuid': 'no-existe',
        'producto_id': 1,
        'nombre_producto': 'x',
        'cantidad': 1,
        'precio_unitario_centavos': 100,
      }),
      throwsA(anything),
    );
  });

  test('VENTA_CONTADO: guarda cabecera, ítems y cola en una transacción', () async {
    final colaId = await cola.guardarOperacionOffline(_operacion(), 'op-1', Schema.tipoVentaContado, null);

    expect(colaId, isNotEmpty);
    expect(await contar(Schema.tablaOperaciones), 1);
    expect(await contar(Schema.tablaOperacionesItems), 2);

    final pendientes = await cola.obtenerOperacionesPendientes();
    expect(pendientes, hasLength(1));
    expect(pendientes.first['estado'], 'pendiente');
    expect(pendientes.first['operacion_uuid'], 'op-1');

    final cab = (await (await appDb.database)!.query(Schema.tablaOperaciones)).single;
    expect(cab['total_centavos'], 2 * 1999 + 5999);
    expect(cab['cliente_id'], isNull);
  });

  test('RESERVA_CLIENTE: exige cliente y no exige cajero', () async {
    await expectLater(
      cola.guardarOperacionOffline(_operacion(cajeroId: null), 'op-2', Schema.tipoReservaCliente, null),
      throwsArgumentError,
    );
    await cola.guardarOperacionOffline(_operacion(cajeroId: null), 'op-3', Schema.tipoReservaCliente, 55);

    final cab = (await (await appDb.database)!.query(Schema.tablaOperaciones)).single;
    expect(cab['cliente_id'], 55);
    expect(cab['cajero_id'], isNull);
  });

  test('VENTA_CONTADO sin cajero y tipos inválidos se rechazan', () async {
    await expectLater(
      cola.guardarOperacionOffline(_operacion(cajeroId: null), 'op-4', Schema.tipoVentaContado, null),
      throwsArgumentError,
    );
    await expectLater(
      cola.guardarOperacionOffline(_operacion(), 'op-5', 'OTRO', null),
      throwsArgumentError,
    );
    expect(await contar(Schema.tablaOperaciones), 0);
  });

  test('si falla el último paso no queda nada a medias (rollback)', () async {
    await cola.guardarOperacionOffline(_operacion(), 'op-6', Schema.tipoVentaContado, null);
    // mismo uuid: la cabecera choca con la clave primaria
    await expectLater(
      cola.guardarOperacionOffline(_operacion(), 'op-6', Schema.tipoVentaContado, null),
      throwsA(anything),
    );
    expect(await contar(Schema.tablaOperaciones), 1);
    expect(await contar(Schema.tablaOperacionesItems), 2);
    expect(await contar(Schema.tablaSyncQueue), 1);

    // ítem con cantidad 0: viola el CHECK a mitad de la transacción (ya insertada la cabecera)
    final malos = [
      {'producto_id': 1, 'nombre_producto': 'ok', 'cantidad': 1, 'precio_unitario_centavos': 10},
      {'producto_id': 2, 'nombre_producto': 'mal', 'cantidad': 0, 'precio_unitario_centavos': 10},
    ];
    await expectLater(
      cola.guardarOperacionOffline(_operacion(items: malos), 'op-7', Schema.tipoVentaContado, null),
      throwsA(anything),
    );
    expect(await contar(Schema.tablaOperaciones), 1);
    expect(await contar(Schema.tablaSyncQueue), 1);
  });

  test('una operación en la cola no se puede borrar de operaciones_locales (RESTRICT)', () async {
    await cola.guardarOperacionOffline(_operacion(), 'op-8', Schema.tipoVentaContado, null);
    final db = (await appDb.database)!;
    await expectLater(db.delete(Schema.tablaOperaciones, where: 'uuid = ?', whereArgs: ['op-8']), throwsA(anything));
  });

  test('catálogo: guarda, lee y un lote inválido deja intacta la caché anterior', () async {
    await cargarCatalogoMock(dao: catalogo);
    final productos = await catalogo.obtenerProductos();
    expect(productos, hasLength(10));
    expect(await catalogo.obtenerProductos(sucursalId: 99), isEmpty);

    // inventario_id duplicado → falla y se revierte el DELETE
    final base = {
      'sucursal_id': 1, 'producto_id': 1, 'nombre_producto': 'a',
      'precio_centavos': 100, 'cantidad_disponible': 1,
    };
    await expectLater(
      catalogo.guardarLoteCatalogo([
        {...base, 'inventario_id': 1},
        {...base, 'inventario_id': 1, 'producto_id': 2},
      ]),
      throwsA(anything),
    );
    expect(await catalogo.obtenerProductos(), hasLength(10));

    // lote vacío: no borra
    await catalogo.guardarLoteCatalogo([]);
    expect(await catalogo.obtenerProductos(), hasLength(10));

    // lote válido: reemplaza
    await catalogo.guardarLoteCatalogo([
      {...base, 'inventario_id': 1},
    ]);
    expect(await catalogo.obtenerProductos(), hasLength(1));
  });

  group('reserva offline con descuento optimista', () {
    late CatalogoOfflineProvider provider;

    setUp(() async {
      provider = CatalogoOfflineProvider(catalogoDao: catalogo, colaDao: cola);
      await provider.cargarDatosMock();
    });

    test('reservar resta 1 al stock local y encola RESERVA_CLIENTE', () async {
      final camiseta = provider.productos.firstWhere((p) => p.productoId == 101);
      final antes = camiseta.cantidadDisponible;

      expect(await provider.reservarProducto(camiseta, 55), isTrue);

      final despues = provider.productos.firstWhere((p) => p.productoId == 101);
      expect(despues.cantidadDisponible, antes - 1);
      expect(provider.pendientes, 1);
      final cab = (await (await appDb.database)!.query(Schema.tablaOperaciones)).single;
      expect(cab['tipo_operacion'], Schema.tipoReservaCliente);
      expect(cab['cliente_id'], 55);
      expect(cab['cajero_id'], isNull);
    });

    test('sin stock no reserva ni encola', () async {
      final agotada = provider.productos.firstWhere((p) => p.productoId == 107); // stock 0
      expect(agotada.hayStock, isFalse);

      expect(await provider.reservarProducto(agotada, 55), isFalse);
      expect(provider.pendientes, 0);
      expect(await contar(Schema.tablaOperaciones), 0);
    });

    test('stock agotado entre medias: rollback completo y stock nunca negativo', () async {
      final abrigo = provider.productos.firstWhere((p) => p.productoId == 110); // stock 2
      expect(await provider.reservarProducto(abrigo, 55), isTrue);
      expect(await provider.reservarProducto(abrigo, 55), isTrue);

      // el objeto `abrigo` está desactualizado (dice stock 2): el UPDATE condicional lo detiene
      expect(await provider.reservarProducto(abrigo, 55), isFalse);
      expect(provider.ultimoMensaje, contains('stock'));
      expect(await contar(Schema.tablaOperaciones), 2);
      expect(await contar(Schema.tablaSyncQueue), 2);
      expect(provider.productos.firstWhere((p) => p.productoId == 110).cantidadDisponible, 0);
    });

    test('el descuento exige inventario_id en los ítems', () async {
      await expectLater(
        cola.guardarOperacionOffline(_operacion(), 'op-x', Schema.tipoVentaContado, null, descontarStockLocal: true),
        throwsArgumentError,
      );
      expect(await contar(Schema.tablaOperaciones), 0);
    });
  });

  group('venta de contado offline (POS)', () {
    late VentaOfflineProvider pos;

    setUp(() async {
      pos = VentaOfflineProvider(catalogoDao: catalogo, colaDao: cola);
      await pos.cargarDatosMock(1);
    });

    CatalogoItem prod(int productoId) => pos.productos.firstWhere((p) => p.productoId == productoId);

    test('parseMonto entiende punto, coma y rechaza basura', () {
      expect(VentaOfflineProvider.parseMonto('20'), 2000);
      expect(VentaOfflineProvider.parseMonto('20.5'), 2050);
      expect(VentaOfflineProvider.parseMonto('20,05'), 2005);
      expect(VentaOfflineProvider.parseMonto('abc'), isNull);
      expect(VentaOfflineProvider.parseMonto('1.234'), isNull);
      expect(VentaOfflineProvider.parseMonto('-5'), isNull);
    });

    test('carrito: agrega, suma, quita y respeta el stock', () {
      final abrigo = prod(110); // stock 2, 129.99
      expect(pos.agregarProducto(abrigo), isTrue);
      expect(pos.agregarProducto(abrigo), isTrue);
      expect(pos.agregarProducto(abrigo), isFalse); // no hay un tercero
      expect(pos.cantidadEnCarrito(abrigo), 2);
      expect(pos.calcularTotal(), 2 * 12999);

      pos.quitarProducto(abrigo);
      expect(pos.cantidadEnCarrito(abrigo), 1);
      pos.quitarProducto(abrigo);
      expect(pos.carritoVacio, isTrue);

      expect(pos.agregarProducto(prod(107)), isFalse); // agotado
      pos.agregarProducto(prod(101));
      pos.limpiarCarrito();
      expect(pos.carritoVacio, isTrue);
    });

    test('cobrar: guarda VENTA_CONTADO, descuenta cada ítem y vacía el carrito', () async {
      final camiseta = prod(101);
      final jean = prod(103);
      final stockCamiseta = camiseta.cantidadDisponible;
      final stockJean = jean.cantidadDisponible;
      pos
        ..agregarProducto(camiseta)
        ..agregarProducto(camiseta)
        ..agregarProducto(jean);
      final total = pos.calcularTotal();

      expect(await pos.procesarVenta(cajeroId: 7, sucursalId: 1, montoRecibidoCentavos: 20000), isTrue);

      expect(pos.carritoVacio, isTrue);
      expect(prod(101).cantidadDisponible, stockCamiseta - 2);
      expect(prod(103).cantidadDisponible, stockJean - 1);
      final cab = (await (await appDb.database)!.query(Schema.tablaOperaciones)).single;
      expect(cab['tipo_operacion'], Schema.tipoVentaContado);
      expect(cab['cajero_id'], 7);
      expect(cab['cliente_id'], isNull);
      expect(cab['total_centavos'], total);
      expect(await contar(Schema.tablaOperacionesItems), 2);
      expect((await cola.obtenerOperacionesPendientes()), hasLength(1));
    });

    test('monto recibido menor al total o carrito vacío: no guarda nada', () async {
      expect(await pos.procesarVenta(cajeroId: 7, sucursalId: 1), isFalse); // vacío
      pos.agregarProducto(prod(101));
      expect(await pos.procesarVenta(cajeroId: 7, sucursalId: 1, montoRecibidoCentavos: 100), isFalse);
      expect(pos.carritoVacio, isFalse); // el carrito se conserva
      expect(await contar(Schema.tablaOperaciones), 0);
    });

    test('stock consumido por otra operación: rollback total y el carrito se ajusta', () async {
      final abrigo = prod(110); // stock 2
      pos.agregarProducto(abrigo);
      pos.agregarProducto(abrigo);
      pos.agregarProducto(prod(101));

      // otra operación offline se lleva 1 abrigo antes de cobrar
      await cola.guardarOperacionOffline({
        'sucursal_id': 1,
        'cajero_id': 9,
        'items': [
          {'inventario_id': abrigo.inventarioId, 'producto_id': 110, 'nombre_producto': 'x', 'cantidad': 1, 'precio_unitario_centavos': 1},
        ],
      }, 'otra', Schema.tipoVentaContado, null, descontarStockLocal: true);

      expect(await pos.procesarVenta(cajeroId: 7, sucursalId: 1), isFalse);
      expect(await contar(Schema.tablaOperaciones), 1); // solo la "otra"
      expect(prod(101).cantidadDisponible, 25); // la camiseta NO se descontó (rollback)
      expect(pos.cantidadEnCarrito(prod(110)), 1); // recortado al stock real
      expect(pos.cantidadEnCarrito(prod(101)), 1);
      expect(pos.ultimoMensaje, contains('stock'));
    });
  });

  test('catálogo: la misma variante no se puede repetir (índice único con NULL)', () async {
    final base = {
      'sucursal_id': 1, 'producto_id': 1, 'nombre_producto': 'a',
      'precio_centavos': 100, 'cantidad_disponible': 1,
    };
    await expectLater(
      catalogo.guardarLoteCatalogo([
        {...base, 'inventario_id': 1},
        {...base, 'inventario_id': 2}, // misma sucursal/producto, talla y color NULL
      ]),
      throwsA(anything),
    );
  });
}
