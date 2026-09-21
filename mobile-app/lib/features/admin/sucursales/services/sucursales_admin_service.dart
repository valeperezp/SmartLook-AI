import '../../../../core/models/sucursal.dart';
import '../../../../core/network/dio_client.dart';

class SucursalesAdminService {
  final DioClient _client = DioClient();

  /// Obtiene la lista completa de sucursales.
  Future<List<Sucursal>> listar() async {
    final response = await _client.get('/sucursales');
    final list = response.data as List<dynamic>? ?? [];
    return list
        .map((e) => Sucursal.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Crea una nueva sucursal.
  Future<Sucursal> crear(Map<String, dynamic> datos) async {
    final response = await _client.post('/sucursales', data: datos);
    return Sucursal.fromJson(response.data as Map<String, dynamic>);
  }

  /// Actualiza una sucursal existente.
  Future<Sucursal> actualizar(int id, Map<String, dynamic> datos) async {
    final response = await _client.put('/sucursales/$id', data: datos);
    return Sucursal.fromJson(response.data as Map<String, dynamic>);
  }

  /// Desactiva o elimina una sucursal.
  Future<Sucursal> desactivar(int id) async {
    final response = await _client.delete('/sucursales/$id');
    return Sucursal.fromJson(response.data as Map<String, dynamic>);
  }
}
