import 'package:flutter/foundation.dart';
import '../services/reportes_chat_service.dart';

class ReportesChatProvider extends ChangeNotifier {
  final ReportesChatService _service = ReportesChatService();

  final List<ChatReportesItem> _mensajes = [
    const ChatReportesItem(
      autor: 'bot',
      texto:
          '¡Hola! Soy tu asistente inteligente de reportes. Podés consultarme métricas de ventas, inventario, reservas, estados o pedirme un resumen ejecutivo del día.',
    ),
  ];

  List<String> _sugerencias = [
    'Generame un resumen del día',
    '¿Qué productos tienen stock bajo?',
    '¿Cómo van las reservas esta semana?',
    '¿Cuáles son los productos más pedidos?',
  ];

  bool _enviando = false;
  String? _errorMessage;

  List<ChatReportesItem> get mensajes => _mensajes;
  List<String> get sugerencias => _sugerencias;
  bool get enviando => _enviando;
  String? get errorMessage => _errorMessage;

  Future<void> enviarMensaje(String texto, {int? sucursalId}) async {
    final mensajeLimpio = texto.trim();
    if (mensajeLimpio.isEmpty || _enviando) return;

    _mensajes.add(ChatReportesItem(autor: 'usuario', texto: mensajeLimpio));
    _enviando = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final respuesta = await _service.enviarConsulta(
        mensaje: mensajeLimpio,
        historial: _mensajes.take(_mensajes.length - 1).toList(),
        sucursalId: sucursalId,
      );

      _mensajes.add(ChatReportesItem(autor: 'bot', texto: respuesta.respuesta));
      if (respuesta.sugerencias.isNotEmpty) {
        _sugerencias = respuesta.sugerencias;
      }
    } catch (e) {
      _errorMessage = 'No se pudo obtener respuesta de la IA: $e';
      _mensajes.add(const ChatReportesItem(
        autor: 'bot',
        texto:
            'Ocurrió un problema al consultar el servicio de IA. Verificá que el modelo esté activo.',
      ));
    } finally {
      _enviando = false;
      notifyListeners();
    }
  }

  void limpiarChat() {
    _mensajes.clear();
    _mensajes.add(const ChatReportesItem(
      autor: 'bot',
      texto:
          '¡Hola! Soy tu asistente inteligente de reportes. Podés consultarme métricas de ventas, inventario, reservas o pedirme un resumen del negocio.',
    ));
    _sugerencias = [
      'Generame un resumen del día',
      '¿Qué productos tienen stock bajo?',
      '¿Cómo van las reservas esta semana?',
    ];
    _errorMessage = null;
    notifyListeners();
  }
}
