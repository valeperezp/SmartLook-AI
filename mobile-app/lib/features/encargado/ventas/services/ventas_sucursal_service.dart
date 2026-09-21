import '../../../../core/models/venta.dart';
import '../../../../core/network/dio_client.dart';
import '../../../checkout/models/pago.dart';

class VentasSucursalService {
  final DioClient _client = DioClient();

  /// Obtiene la lista de ventas de una sucursal específica.
  Future<List<Venta>> listarVentas(int sucursalId) async {
    final response = await _client.get('/ventas/sucursal/$sucursalId');
    if (response.data is List) {
      return (response.data as List)
          .map((json) => Venta.fromJson(json as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  /// Obtiene los pagos registrados asociados a una venta.
  Future<List<Pago>> listarPagosVenta(int ventaId) async {
    final response = await _client.get('/pagos/venta/$ventaId');
    if (response.data is List) {
      return (response.data as List)
          .map((json) => Pago.fromJson(json as Map<String, dynamic>))
          .toList();
    }
    return [];
  }
}
