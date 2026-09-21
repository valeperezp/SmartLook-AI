import '../../../core/models/venta.dart';
import '../../../core/network/dio_client.dart';

class VentasService {
  final DioClient _dioClient = DioClient();

  /// Lista las compras online del cliente autenticado.
  Future<List<Venta>> listarMisCompras() async {
    final response = await _dioClient.get('/ventas/mis-compras');
    if (response.data is List) {
      return (response.data as List)
          .map((json) => Venta.fromJson(json as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  /// Obtiene el detalle de una venta por ID.
  Future<Venta> obtenerVenta(int id) async {
    final response = await _dioClient.get('/ventas/$id');
    return Venta.fromJson(response.data as Map<String, dynamic>);
  }
}
