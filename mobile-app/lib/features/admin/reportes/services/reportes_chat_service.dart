import '../../../../core/network/dio_client.dart';

class ChatReportesItem {
  final String autor; // 'usuario' o 'bot'
  final String texto;

  const ChatReportesItem({
    required this.autor,
    required this.texto,
  });

  Map<String, dynamic> toJson() => {
        'autor': autor,
        'texto': texto,
      };

  factory ChatReportesItem.fromJson(Map<String, dynamic> json) =>
      ChatReportesItem(
        autor: json['autor']?.toString() ?? 'bot',
        texto: json['texto']?.toString() ?? '',
      );
}

class ChatReportesResponse {
  final String respuesta;
  final List<String> sugerencias;

  const ChatReportesResponse({
    required this.respuesta,
    required this.sugerencias,
  });

  factory ChatReportesResponse.fromJson(Map<String, dynamic> json) {
    final list = json['sugerencias'] as List<dynamic>? ?? [];
    return ChatReportesResponse(
      respuesta: json['respuesta']?.toString() ?? '',
      sugerencias: list.map((e) => e.toString()).toList(),
    );
  }
}

class ReportesChatService {
  final DioClient _client = DioClient();

  Future<ChatReportesResponse> enviarConsulta({
    required String mensaje,
    List<ChatReportesItem> historial = const [],
    int? sucursalId,
  }) async {
    final dataMap = <String, dynamic>{
      'mensaje': mensaje,
      'historial': historial.map((h) => h.toJson()).toList(),
    };
    if (sucursalId != null) {
      dataMap['sucursal_id'] = sucursalId;
    }

    final response = await _client.post<Map<String, dynamic>>(
      '/ia/chat-reportes',
      data: dataMap,
    );

    if (response.data == null) {
      throw Exception('Respuesta vacía del asistente de reportes');
    }

    return ChatReportesResponse.fromJson(response.data!);
  }
}
