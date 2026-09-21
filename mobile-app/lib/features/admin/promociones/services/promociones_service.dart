import '../../../../core/network/dio_client.dart';
import '../models/promocion.dart';

class PromocionesService {
  final DioClient _client = DioClient();

  /// Obtiene la lista de promociones (filtrable por activas).
  Future<List<Promocion>> listar({bool soloActivas = false}) async {
    final response = await _client.get(
      '/promociones',
      query: {'solo_activas': soloActivas},
    );
    final list = response.data as List<dynamic>? ?? [];
    return list
        .map((e) => Promocion.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Obtiene una promoción por ID con su detalle.
  Future<Promocion> obtener(int id) async {
    final response = await _client.get('/promociones/$id');
    return Promocion.fromJson(response.data as Map<String, dynamic>);
  }

  /// Crea una nueva promoción.
  Future<Promocion> crear(Map<String, dynamic> datos) async {
    final response = await _client.post('/promociones', data: datos);
    return Promocion.fromJson(response.data as Map<String, dynamic>);
  }

  /// Actualiza una promoción existente.
  Future<Promocion> actualizar(int id, Map<String, dynamic> datos) async {
    final response = await _client.put('/promociones/$id', data: datos);
    return Promocion.fromJson(response.data as Map<String, dynamic>);
  }

  /// Desactiva una promoción (soft-delete).
  Future<Promocion> desactivar(int id) async {
    final response = await _client.delete('/promociones/$id');
    return Promocion.fromJson(response.data as Map<String, dynamic>);
  }

  /// Reactiva una promoción desactivada.
  Future<Promocion> reactivar(int id) async {
    final response = await _client.patch('/promociones/$id/reactivar');
    return Promocion.fromJson(response.data as Map<String, dynamic>);
  }

  /// Actualiza la lista de productos asociados.
  Future<Promocion> actualizarProductos(int id, List<int> productoIds) async {
    final response = await _client.put(
      '/promociones/$id/productos',
      data: {'producto_ids': productoIds},
    );
    return Promocion.fromJson(response.data as Map<String, dynamic>);
  }
}
