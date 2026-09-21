import 'package:flutter/foundation.dart';
import '../models/chat_mensaje.dart';
import '../models/recomendacion.dart';
import '../services/ia_service.dart';

const List<String> sugerenciasIniciales = [
  '¿Qué me recomendás?',
  '¿Cuáles son mis reservas?',
  '¿Dónde están las sucursales?',
  'Busco una camisa',
];

const String saludoInicial =
    '¡Hola! Soy el asistente virtual de SmartLook AI. Puedo ayudarte a buscar prendas, '
    'darte recomendaciones, o contarte sobre tus reservas y sucursales. ¿En qué te ayudo?';

class IaProvider extends ChangeNotifier {
  final IaService _service = IaService();

  List<ChatMensaje> _mensajes = [
    ChatMensaje.asistente(saludoInicial),
  ];
  List<String> _sugerencias = List.from(sugerenciasIniciales);
  List<Recomendacion> _recomendaciones = [];

  bool _cargandoMensaje = false;
  bool _cargandoRecomendaciones = false;
  String? _errorChat;
  String? _errorRecomendaciones;

  // Getters
  List<ChatMensaje> get mensajes => _mensajes;
  List<String> get sugerencias => _sugerencias;
  List<Recomendacion> get recomendaciones => _recomendaciones;
  bool get cargandoMensaje => _cargandoMensaje;
  bool get cargandoRecomendaciones => _cargandoRecomendaciones;
  String? get errorChat => _errorChat;
  String? get errorRecomendaciones => _errorRecomendaciones;

  Future<void> cargarRecomendaciones({int limit = 8}) async {
    _cargandoRecomendaciones = true;
    _errorRecomendaciones = null;
    notifyListeners();

    try {
      final list = await _service.obtenerRecomendaciones(limit: limit);
      _recomendaciones = list;
    } catch (e) {
      _errorRecomendaciones = 'No se pudieron cargar recomendaciones personalizadas';
      debugPrint('Error cargando recomendaciones: $e');
    } finally {
      _cargandoRecomendaciones = false;
      notifyListeners();
    }
  }

  Future<void> enviarMensaje(String textoCrudo) async {
    final texto = textoCrudo.trim();
    if (texto.isEmpty || _cargandoMensaje) return;

    // Obtener los últimos 6 turnos de conversación para el contexto
    final historial = _mensajes.length > 6
        ? _mensajes.sublist(_mensajes.length - 6)
        : List<ChatMensaje>.from(_mensajes);

    _mensajes.add(ChatMensaje.usuario(texto));
    _cargandoMensaje = true;
    _errorChat = null;
    notifyListeners();

    try {
      final respuesta = await _service.enviarMensaje(
        texto: texto,
        historial: historial,
      );

      _mensajes.add(ChatMensaje.asistente(respuesta.respuesta));
      if (respuesta.sugerencias.isNotEmpty) {
        _sugerencias = List.from(respuesta.sugerencias);
      } else {
        _sugerencias = List.from(sugerenciasIniciales);
      }
    } catch (e) {
      _errorChat = 'No pudimos conectar con el asistente virtual.';
      _mensajes.add(
        ChatMensaje.asistente(
          'Uy, tuve un problema para procesar tu consulta. Por favor intentá de nuevo en unos momentos.',
        ),
      );
    } finally {
      _cargandoMensaje = false;
      notifyListeners();
    }
  }

  void limpiarHistorial() {
    _mensajes = [
      ChatMensaje.asistente(saludoInicial),
    ];
    _sugerencias = List.from(sugerenciasIniciales);
    _errorChat = null;
    notifyListeners();
  }
}
