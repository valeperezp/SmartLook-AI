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

  /// Genera la prueba virtual con IA en el backend (flujo asíncrono Fase 2).
  ///
  /// Fase 1: POST /vestidor/generar → recibe { job_id } en <5 s.
  /// Fase 2: polling GET /vestidor/job/{job_id} hasta estado
  ///         completado | fallido o timeout de 5 min.
  Future<VestidorPrueba> generarPruebaVirtual({
    required int productoId,
    required Uint8List fotoBytes,
    String nombreArchivo = 'persona.jpg',
    void Function(String estado)? onEstado,
  }) async {
    // ===== FASE 1: POST — crear job (responde en <5s) =====
    final formData = FormData.fromMap({
      'producto_id': productoId,
      'foto': MultipartFile.fromBytes(
        fotoBytes,
        filename: nombreArchivo,
      ),
    });

    final postResponse = await _client.post<Map<String, dynamic>>(
      '/vestidor/generar',
      data: formData,
      options: Options(
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 60),
      ),
    );

    final postData = postResponse.data;
    if (postData == null) {
      throw Exception('Respuesta vacía del servidor al crear el job');
    }

    final jobId = postData['job_id'] as int?;
    if (jobId == null) {
      throw Exception('El servidor no devolvió job_id');
    }

    // ===== FASE 2: Polling GET /vestidor/job/{jobId} =====
    final deadline = DateTime.now().add(const Duration(minutes: 5));
    String? ultimoEstado;

    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(seconds: 2));

      final jobResponse = await _client.dio.get<Map<String, dynamic>>(
        '/vestidor/job/$jobId',
        options: Options(receiveTimeout: const Duration(seconds: 15)),
      );

      final jobData = jobResponse.data;
      if (jobData == null) continue;

      final estado = jobData['estado'] as String? ?? 'desconocido';

      if (estado != ultimoEstado) {
        ultimoEstado = estado;
        onEstado?.call(estado);
      }

      if (estado == 'completado') {
        return VestidorPrueba(
          imagenResultadoUrl: jobData['imagen_resultado_url'] as String? ?? '',
          productoId: jobData['producto_id'] as int? ?? productoId,
        );
      }

      if (estado == 'fallido') {
        final err = jobData['error'] as String?;
        throw Exception(err ?? 'La generación con IA falló');
      }

      // 'pendiente' o 'procesando' → seguir esperando
    }

    throw Exception(
      'La generación tardó más de 5 minutos. Reintentá en unos segundos.',
    );
  }
}
