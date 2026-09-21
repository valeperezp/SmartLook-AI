import '../../../core/models/venta.dart';
import '../../../core/network/dio_client.dart';
import '../models/venta_online.dart';

class VentasOnlineService {
  final DioClient _client = DioClient();

  Future<Venta> crearVentaOnline(VentaOnlineCreate data) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/ventas/online',
      data: data.toJson(),
    );

    if (response.data == null) {
      throw Exception('Respuesta vacía del servidor al crear venta online');
    }

    return Venta.fromJson(response.data!);
  }
}
