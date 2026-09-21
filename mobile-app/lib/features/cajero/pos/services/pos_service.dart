import '../../../../core/models/categoria.dart';
import '../../../../core/models/disponibilidad.dart';
import '../../../../core/models/producto.dart';
import '../../../../core/models/venta.dart';
import '../../../../core/network/dio_client.dart';

class PosService {
  final DioClient _client = DioClient();

  /// Crea una venta presencial (CU17) en el servidor.
  Future<Venta> crearVentaPresencial({
    required int sucursalId,
    int? clienteId,
    required List<Map<String, dynamic>> items,
  }) async {
    final payload = {
      'sucursal_id': sucursalId,
      'cliente_id': clienteId,
      'items': items,
    };

    final response = await _client.post('/ventas', data: payload);
    if (response.data == null) {
      throw Exception('Error al registrar venta presencial');
    }
    return Venta.fromJson(response.data as Map<String, dynamic>);
  }

  /// Busca productos en el catálogo filtrando por sucursal, categoría o término de búsqueda.
  Future<List<Producto>> buscarProductos({
    int? sucursalId,
    int? categoriaId,
    String? query,
  }) async {
    final params = <String, dynamic>{};
    if (sucursalId != null) params['sucursal_id'] = sucursalId;
    if (categoriaId != null) params['categoria_id'] = categoriaId;

    final response = await _client.get('/catalogo/productos', query: params.isNotEmpty ? params : null);

    if (response.data is List) {
      var list = (response.data as List)
          .map((json) => Producto.fromJson(json as Map<String, dynamic>))
          .toList();

      if (query != null && query.trim().isNotEmpty) {
        final q = query.toLowerCase().trim();
        list = list.where((p) {
          final nombreMatch = p.nombre.toLowerCase().contains(q);
          final descMatch = p.descripcion?.toLowerCase().contains(q) ?? false;
          final catMatch = p.categoriaNombre.toLowerCase().contains(q);
          return nombreMatch || descMatch || catMatch;
        }).toList();
      }

      return list;
    }
    return [];
  }

  /// Consulta la disponibilidad de stock por tallas y colores de un producto.
  Future<ProductoDisponibilidad> consultarStock(int productoId) async {
    final response = await _client.get('/catalogo/productos/$productoId/disponibilidad');
    return ProductoDisponibilidad.fromJson(response.data as Map<String, dynamic>);
  }

  /// Lista categorías activas para filtrar el catálogo en el POS.
  Future<List<Categoria>> listarCategorias() async {
    final response = await _client.get('/catalogo/categorias');
    if (response.data is List) {
      return (response.data as List)
          .map((json) => Categoria.fromJson(json as Map<String, dynamic>))
          .where((c) => c.activo)
          .toList();
    }
    return [];
  }
}
