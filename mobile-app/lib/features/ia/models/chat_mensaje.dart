enum RolMensaje { user, assistant }

class ChatMensaje {
  final RolMensaje rol;
  final String contenido;
  final DateTime timestamp;

  ChatMensaje({
    required this.rol,
    required this.contenido,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  bool get esUsuario => rol == RolMensaje.user;
  bool get esAsistente => rol == RolMensaje.assistant;

  Map<String, dynamic> toHistorialJson() {
    return {
      'autor': esUsuario ? 'usuario' : 'bot',
      'texto': contenido,
    };
  }

  factory ChatMensaje.usuario(String texto) {
    return ChatMensaje(
      rol: RolMensaje.user,
      contenido: texto,
    );
  }

  factory ChatMensaje.asistente(String texto) {
    return ChatMensaje(
      rol: RolMensaje.assistant,
      contenido: texto,
    );
  }
}

class ChatRespuesta {
  final String respuesta;
  final String intencion;
  final List<String> sugerencias;

  ChatRespuesta({
    required this.respuesta,
    required this.intencion,
    required this.sugerencias,
  });

  factory ChatRespuesta.fromJson(Map<String, dynamic> json) {
    final rawSugerencias = json['sugerencias'] as List<dynamic>? ?? [];
    return ChatRespuesta(
      respuesta: json['respuesta'] as String? ?? '',
      intencion: json['intencion'] as String? ?? '',
      sugerencias: rawSugerencias.map((e) => e.toString()).toList(),
    );
  }
}
