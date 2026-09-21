import '../../../core/network/dio_client.dart';
import '../models/producto_ar.dart';

class VestidorService {
  final DioClient _client = DioClient();

  Future<ProductoAr> obtenerProductoAR(int productoId) async {
    final response = await _client.get<Map<String, dynamic>>(
      '/catalogo/productos/$productoId',
    );

    if (response.data == null) {
      throw Exception('Producto no encontrado');
    }

    return ProductoAr.fromJson(response.data!);
  }

  Future<List<ProductoAr>> listarProductos() async {
    final response = await _client.get<List<dynamic>>(
      '/catalogo/productos',
    );

    final list = response.data ?? [];
    return list
        .map((item) => ProductoAr.fromJson(item as Map<String, dynamic>))
        .toList();
  }
}
