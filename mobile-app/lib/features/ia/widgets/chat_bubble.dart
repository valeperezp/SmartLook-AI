import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/chat_mensaje.dart';

class ChatBubble extends StatelessWidget {
  final ChatMensaje mensaje;

  const ChatBubble({
    super.key,
    required this.mensaje,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final esUsuario = mensaje.esUsuario;
    final timeStr = DateFormat('HH:mm').format(mensaje.timestamp);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment:
            esUsuario ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!esUsuario) ...[
            Container(
              width: 28,
              height: 28,
              margin: const EdgeInsets.only(right: 6, bottom: 2),
              decoration: BoxDecoration(
                color: Colors.purple.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.auto_awesome, size: 16, color: Colors.purple.shade800),
            ),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: esUsuario
                    ? theme.colorScheme.primary
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(esUsuario ? 16 : 4),
                  bottomRight: Radius.circular(esUsuario ? 4 : 16),
                ),
                border: esUsuario
                    ? null
                    : Border.all(color: Colors.grey.shade300),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: esUsuario
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    mensaje.contenido,
                    style: TextStyle(
                      fontSize: 14,
                      color: esUsuario ? Colors.white : Colors.black87,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    timeStr,
                    style: TextStyle(
                      fontSize: 10,
                      color: esUsuario
                          ? Colors.white.withValues(alpha: 0.7)
                          : Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (esUsuario) ...[
            const SizedBox(width: 4),
          ],
        ],
      ),
    );
  }
}
