import '../network/dio_client.dart';

class AdminService {
  final DioClient _dioClient = DioClient();

  Future<Map<String, dynamic>> obtenerResumenInventario() async {
    final response = await _dioClient.get('/inventario/resumen');
    return response.data as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> listarUsuarios() async {
    final response = await _dioClient.get('/usuarios');
    if (response.data is List) {
      return (response.data as List)
          .map((item) => item as Map<String, dynamic>)
          .toList();
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> listarInventarioAlertas() async {
    final response = await _dioClient.get('/inventario/alertas');
    if (response.data is List) {
      return (response.data as List)
          .map((item) => item as Map<String, dynamic>)
          .toList();
    }
    return [];
  }

  Future<List<dynamic>> listarProductos() async {
    final response = await _dioClient.get('/catalogo/productos');
    if (response.data is List) {
      return response.data as List<dynamic>;
    }
    return [];
  }

  Future<List<dynamic>> listarSucursales() async {
    final response = await _dioClient.get('/sucursales');
    if (response.data is List) {
      return response.data as List<dynamic>;
    }
    return [];
  }

  Future<List<dynamic>> listarInventarioGlobal() async {
    final response = await _dioClient.get('/inventario');
    if (response.data is List) {
      return response.data as List<dynamic>;
    }
    return [];
  }
}
