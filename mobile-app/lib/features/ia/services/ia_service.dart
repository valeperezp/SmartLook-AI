import '../../../core/network/dio_client.dart';
import '../models/chat_mensaje.dart';
import '../models/recomendacion.dart';

class IaService {
  final DioClient _client = DioClient();

  Future<ChatRespuesta> enviarMensaje({
    required String texto,
    List<ChatMensaje> historial = const [],
  }) async {
    final historialJson = historial.map((m) => m.toHistorialJson()).toList();

    final response = await _client.post<Map<String, dynamic>>(
      '/ia/chat',
      data: {
        'mensaje': texto,
        'historial': historialJson,
      },
    );

    if (response.data == null) {
      throw Exception('Respuesta vacía del asistente virtual');
    }

    return ChatRespuesta.fromJson(response.data!);
  }

  Future<List<Recomendacion>> obtenerRecomendaciones({int limit = 8}) async {
    final response = await _client.get<List<dynamic>>(
      '/ia/recomendaciones',
      query: {'limit': limit},
    );

    final list = response.data ?? [];
    return list
        .map((item) => Recomendacion.fromJson(item as Map<String, dynamic>))
        .toList();
  }
}
