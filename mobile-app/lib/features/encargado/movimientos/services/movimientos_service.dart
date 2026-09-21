import '../../../../core/network/dio_client.dart';
import '../models/movimiento_inventario.dart';

class MovimientosService {
  final DioClient _client = DioClient();

  /// Obtiene la lista de movimientos de inventario según filtros.
  Future<List<MovimientoInventario>> listarMovimientos({
    int? sucursalId,
    int? inventarioId,
    String? tipo,
    int limit = 100,
  }) async {
    final query = <String, dynamic>{'limit': limit};
    if (sucursalId != null) query['sucursal_id'] = sucursalId;
    if (inventarioId != null) query['inventario_id'] = inventarioId;
    if (tipo != null && tipo.isNotEmpty && tipo != 'todos') {
      query['tipo'] = tipo;
    }

    final response = await _client.get(
      '/inventario/movimientos',
      query: query,
    );

    final list = response.data as List<dynamic>? ?? [];
    return list
        .map((e) => MovimientoInventario.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
