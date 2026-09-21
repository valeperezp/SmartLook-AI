import '../network/dio_client.dart';

class ProveedorService {
  final DioClient _dioClient = DioClient();

  /// Lista los productos del catálogo pertenecientes al proveedor autenticado.
  Future<List<dynamic>> listarMisProductos({bool incluirInactivos = true}) async {
    final response = await _dioClient.get(
      '/catalogo/mis-productos?incluir_inactivos=$incluirInactivos',
    );
    if (response.data is List) {
      return response.data as List<dynamic>;
    }
    return [];
  }

  /// Lista las categorías del catálogo.
  Future<List<dynamic>> listarCategorias() async {
    final response = await _dioClient.get('/catalogo/categorias');
    if (response.data is List) {
      return response.data as List<dynamic>;
    }
    return [];
  }

  /// Lista las temporadas registradas.
  Future<List<dynamic>> listarTemporadas() async {
    final response = await _dioClient.get('/catalogo/temporadas');
    if (response.data is List) {
      return response.data as List<dynamic>;
    }
    return [];
  }

  /// Lista las colecciones disponibles.
  Future<List<dynamic>> listarColecciones() async {
    final response = await _dioClient.get('/catalogo/colecciones');
    if (response.data is List) {
      return response.data as List<dynamic>;
    }
    return [];
  }

  /// Lista las tallas disponibles.
  Future<List<dynamic>> listarTallas() async {
    final response = await _dioClient.get('/catalogo/tallas');
    if (response.data is List) {
      return response.data as List<dynamic>;
    }
    return [];
  }

  /// Lista los colores disponibles.
  Future<List<dynamic>> listarColores() async {
    final response = await _dioClient.get('/catalogo/colores');
    if (response.data is List) {
      return response.data as List<dynamic>;
    }
    return [];
  }

  /// Crea un nuevo producto asignado al proveedor autenticado.
  Future<dynamic> crearProducto(Map<String, dynamic> data) async {
    final response = await _dioClient.post('/catalogo/mis-productos', data: data);
    return response.data;
  }

  /// Actualiza un producto del proveedor.
  Future<dynamic> actualizarProducto(int id, Map<String, dynamic> data) async {
    final response = await _dioClient.put('/catalogo/mis-productos/$id', data: data);
    return response.data;
  }

  /// Desactiva (soft-delete) un producto del proveedor.
  Future<dynamic> desactivarProducto(int id) async {
    final response = await _dioClient.delete('/catalogo/mis-productos/$id');
    return response.data;
  }
}
