import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../../../core/network/dio_client.dart';
import '../models/producto_ar.dart';
import '../models/vestidor_prueba.dart';

class VestidorService {
  final DioClient _client = DioClient();

  /// Obtiene los datos del producto para el vestidor
  Future<ProductoAr> obtenerProductoAR(int productoId) async {
    final response = await _client.get<Map<String, dynamic>>(
      '/catalogo/productos/$productoId',
    );

    if (response.data == null) {
      throw Exception('Producto no encontrado');
    }

    return ProductoAr.fromJson(response.data!);
  }

  /// Lista el catálogo de prendas disponibles para probar
  Future<List<ProductoAr>> listarProductos() async {
    final response = await _client.get<List<dynamic>>(
      '/catalogo/productos',
    );

    final list = response.data ?? [];
    return list
        .map((item) => ProductoAr.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  /// Genera la prueba virtual con IA en el backend (POST /vestidor/generar)
  Future<VestidorPrueba> generarPruebaVirtual({
    required int productoId,
    required Uint8List fotoBytes,
    String nombreArchivo = 'persona.jpg',
  }) async {
    final formData = FormData.fromMap({
      'producto_id': productoId,
      'foto': MultipartFile.fromBytes(
        fotoBytes,
        filename: nombreArchivo,
      ),
    });

    final response = await _client.post<Map<String, dynamic>>(
      '/vestidor/generar',
      data: formData,
      // Replicate (IDM-VTON) puede tardar 20-45s en generar la imagen — muy por
      // encima del timeout global de 10s del DioClient, pensado para requests normales.
      options: Options(
        receiveTimeout: const Duration(seconds: 180),
        sendTimeout: const Duration(seconds: 60),
      ),
    );

    if (response.data == null) {
      throw Exception('Respuesta vacía del servidor de vestidor virtual');
    }

    return VestidorPrueba.fromJson(response.data!);
  }
}
