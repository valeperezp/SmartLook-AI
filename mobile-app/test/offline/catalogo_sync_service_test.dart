import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlook_mobile/core/database/app_database.dart';
import 'package:smartlook_mobile/core/models/disponibilidad.dart';
import 'package:smartlook_mobile/core/models/producto.dart';
import 'package:smartlook_mobile/core/services/catalogo_service.dart';
import 'package:smartlook_mobile/features/offline/data/catalogo_local_dao.dart';
import 'package:smartlook_mobile/features/offline/data/mock_data.dart';
import 'package:smartlook_mobile/features/offline/services/catalogo_sync_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Producto _producto(int id, String nombre, double precio, {bool activo = true}) => Producto.fromJson({
      'id': id,
      'nombre': nombre,
      'precio': precio,
      'categoria_id': 1,
      'activo': activo,
      'imagen_url': 'http://servidor/img/$id.png',
    });

ProductoDisponibilidad _disp(int productoId, List<DisponibilidadSucursal> sucursales) => ProductoDisponibilidad(
      productoId: productoId,
      nombreProducto: 'x',
      precio: 0,
      totalGlobal: 0,
      sucursalesConStock: 0,
      disponibilidad: sucursales,
    );

DisponibilidadSucursal _suc(int id, List<(int, String, int, String, int)> items) => DisponibilidadSucursal(
      sucursalId: id,
      nombreSucursal: 'Sucursal $id',
      totalDisponible: 0,
      estado: 'disponible',
      items: [
        for (final (tallaId, talla, colorId, color, cantidad) in items)
          DisponibilidadTallaColor(tallaId: tallaId, nombreTalla: talla, colorId: colorId, nombreColor: color, cantidadDisponible: cantidad),
      ],
    );

class _CatalogoFalso extends CatalogoService {
  _CatalogoFalso({this.productos = const [], this.disponibilidades = const {}, this.error});

  final List<Producto> productos;
  final Map<int, ProductoDisponibilidad> disponibilidades;
  final Object? error;

  @override
  Future<List<Producto>> listarProductos({int? categoriaId, int? sucursalId}) async {
    if (error != null) throw error!;
    return productos;
  }

  @override
  Future<ProductoDisponibilidad> obtenerDisponibilidad(int productoId) async => disponibilidades[productoId]!;
}

DioException _sinRed() => DioException(requestOptions: RequestOptions(path: '/catalogo/productos'), type: DioExceptionType.connectionError);

void main() {
  late AppDatabase appDb;
  late CatalogoLocalDao dao;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    appDb = AppDatabase.conBaseDeDatos(await AppDatabase.abrir(inMemoryDatabasePath));
    dao = CatalogoLocalDao(appDatabase: appDb);
  });

  tearDown(() => appDb.cerrar());

  final productos = [_producto(1, 'Camiseta', 89), _producto(2, 'Chaqueta', 450.5), _producto(3, 'Inactiva', 10, activo: false)];
  final disponibilidades = {
    1: _disp(1, [
      _suc(1, [(2, 'M', 1, 'Negro', 52), (3, 'L', 1, 'Negro', 0)]),
      _suc(2, [(2, 'M', 1, 'Negro', 35)]),
    ]),
    2: _disp(2, [
      _suc(1, [(3, 'L', 2, 'Gris', 3)]),
    ]),
  };

  test('descarga el catálogo del servidor y reemplaza los datos de prueba', () async {
    await cargarCatalogoMock(dao: dao, sucursalId: 1);
    expect((await dao.obtenerProductos()).any((f) => f['nombre_producto'] == 'Camiseta básica'), isTrue);

    final servicio = CatalogoSyncService(catalogoService: _CatalogoFalso(productos: productos, disponibilidades: disponibilidades), dao: dao);
    final r = await servicio.descargarCatalogoDesdeServidor();

    final filas = await dao.obtenerProductos();
    expect(r.registros, 4);
    expect(filas.length, 4);
    expect(filas.any((f) => f['nombre_producto'] == 'Camiseta básica'), isFalse, reason: 'el mock ya no está');
    expect(filas.map((f) => f['nombre_producto']).toSet(), {'Camiseta', 'Chaqueta'}, reason: 'los productos inactivos no se guardan');
    final chaqueta = filas.firstWhere((f) => f['nombre_producto'] == 'Chaqueta');
    expect(chaqueta['precio_centavos'], 45050);
    expect(chaqueta['imagen_url'], 'http://servidor/img/2.png');
    expect(chaqueta['cantidad_disponible'], 3);
    // una variante sin stock también se guarda (sirve para "Avísame cuando llegue")
    expect(filas.where((f) => f['cantidad_disponible'] == 0).length, 1);
  });

  test('con sucursalId solo guarda esa sucursal', () async {
    final servicio = CatalogoSyncService(catalogoService: _CatalogoFalso(productos: productos, disponibilidades: disponibilidades), dao: dao);
    final r = await servicio.descargarCatalogoDesdeServidor(sucursalId: 2);

    expect(r.registros, 1);
    final filas = await dao.obtenerProductos();
    expect(filas.single['sucursal_id'], 2);
  });

  test('sin red lanza SinConexionException y conserva el catálogo local', () async {
    await cargarCatalogoMock(dao: dao, sucursalId: 1);
    final antes = await dao.obtenerProductos();

    final servicio = CatalogoSyncService(catalogoService: _CatalogoFalso(error: _sinRed()), dao: dao);
    await expectLater(servicio.descargarCatalogoDesdeServidor(), throwsA(isA<SinConexionException>()));

    expect(await dao.obtenerProductos(), antes);
  });

  test('un error del servidor (500) no se confunde con falta de red', () async {
    final e500 = DioException(
      requestOptions: RequestOptions(path: '/catalogo/productos'),
      type: DioExceptionType.badResponse,
      response: Response(requestOptions: RequestOptions(path: '/catalogo/productos'), statusCode: 500),
    );
    final servicio = CatalogoSyncService(catalogoService: _CatalogoFalso(error: e500), dao: dao);
    await expectLater(servicio.descargarCatalogoDesdeServidor(), throwsA(isA<DioException>()));
  });

  test('si el servidor no devuelve variantes, no borra el catálogo local', () async {
    await cargarCatalogoMock(dao: dao, sucursalId: 1);
    final antes = await dao.obtenerProductos();

    final servicio = CatalogoSyncService(catalogoService: _CatalogoFalso(), dao: dao);
    final r = await servicio.descargarCatalogoDesdeServidor();

    expect(r.registros, 0);
    expect(await dao.obtenerProductos(), antes);
  });

  test('los mensajes para el usuario', () {
    expect(CatalogoSyncService.mensajeDescarga(error: SinConexionException()), 'Sin conexión, usando catálogo local');
    expect(CatalogoSyncService.mensajeDescarga(resultado: const ResultadoDescargaCatalogo(registros: 4)), contains('4 variantes'));
    expect(CatalogoSyncService.mensajeDescarga(resultado: const ResultadoDescargaCatalogo(registros: 0)), contains('catálogo local'));
  });
}
