import '../models/categoria.dart';
import '../models/disponibilidad.dart';
import '../models/producto.dart';
import '../models/sucursal.dart';
import '../network/dio_client.dart';

class CatalogoService {
  final DioClient _dioClient = DioClient();

  Future<List<Categoria>> listarCategorias() async {
    final response = await _dioClient.get('/catalogo/categorias');
    if (response.data is List) {
      return (response.data as List)
          .map((json) => Categoria.fromJson(json as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  Future<List<Producto>> listarProductos({
    int? categoriaId,
    int? sucursalId,
  }) async {
    final queryParams = <String, dynamic>{};
    if (categoriaId != null) queryParams['categoria_id'] = categoriaId;
    if (sucursalId != null) queryParams['sucursal_id'] = sucursalId;

    final response = await _dioClient.get(
      '/catalogo/productos',
      query: queryParams.isNotEmpty ? queryParams : null,
    );

    if (response.data is List) {
      return (response.data as List)
          .map((json) => Producto.fromJson(json as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  Future<Producto> obtenerProducto(int productoId) async {
    final response = await _dioClient.get('/catalogo/productos/$productoId');
    return Producto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<ProductoDisponibilidad> obtenerDisponibilidad(int productoId) async {
    final response =
        await _dioClient.get('/catalogo/productos/$productoId/disponibilidad');
    return ProductoDisponibilidad.fromJson(
        response.data as Map<String, dynamic>);
  }

  Future<List<Sucursal>> listarSucursales() async {
    final response = await _dioClient.get('/sucursales');
    if (response.data is List) {
      return (response.data as List)
          .map((json) => Sucursal.fromJson(json as Map<String, dynamic>))
          .toList();
    }
    return [];
  }
}
