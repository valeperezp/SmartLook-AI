import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../../../core/network/dio_client.dart';
import '../models/producto_ar.dart';
import '../models/vestidor_prueba.dart';

/// El polling se cancelo (nueva generacion, limpiarFoto o 401): no es un error para el usuario.
class GeneracionCancelada implements Exception {}

class VestidorService {
  final DioClient _client = DioClient();
  CancelToken? _cancelToken;
  int _generacionId = 0;

  /// Detiene el polling en curso. El job sigue en el servidor y cuenta en el limite diario.
  void cancelar() {
    _cancelToken?.cancel();
    _generacionId++;
  }

  /// Transitorio = vale la pena reintentar (red, timeouts, 5xx). El resto (401/403/404/4xx) es fatal.
  bool _esTransitorio(DioException e) {
    final codigo = e.response?.statusCode ?? 0;
    return e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        (e.type == DioExceptionType.badResponse && codigo >= 500);
  }

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
    _cancelToken?.cancel();
    final token = _cancelToken = CancelToken();
    final generacion = ++_generacionId;
    void verificarVigente() {
      if (generacion != _generacionId || token.isCancelled) throw GeneracionCancelada();
    }

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
    verificarVigente();
    final reloj = Stopwatch()..start(); // monotonico: no depende del reloj de pared
    String? ultimoEstado;
    var fallosSeguidos = 0;

    while (reloj.elapsed < const Duration(minutes: 5)) {
      // 2 s entre consultas; tras un fallo transitorio, backoff exponencial 2/4/8/16 s.
      await Future.delayed(Duration(seconds: fallosSeguidos == 0 ? 2 : 2 << (fallosSeguidos - 1)));
      verificarVigente();

      final Response<Map<String, dynamic>> jobResponse;
      try {
        jobResponse = await _client.dio.get<Map<String, dynamic>>(
          '/vestidor/job/$jobId',
          options: Options(receiveTimeout: const Duration(seconds: 15)),
          cancelToken: token,
        );
      } on DioException catch (e) {
        if (CancelToken.isCancel(e)) throw GeneracionCancelada();
        // Hasta 5 fallos transitorios seguidos; al agotarlos (o ante un fatal) se relanza el error.
        if (!_esTransitorio(e) || ++fallosSeguidos >= 5) rethrow;
        continue;
      }
      fallosSeguidos = 0;
      verificarVigente();

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
