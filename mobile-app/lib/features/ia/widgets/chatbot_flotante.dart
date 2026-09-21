import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/ia_provider.dart';
import 'chat_bubble.dart';

class ChatbotFlotante extends StatelessWidget {
  const ChatbotFlotante({super.key});

  void _abrirChat(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const _ChatbotBottomSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      onPressed: () => _abrirChat(context),
      backgroundColor: Colors.purple.shade700,
      foregroundColor: Colors.white,
      elevation: 4,
      icon: const Icon(Icons.auto_awesome, size: 20),
      label: const Text(
        'Asistente IA',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _ChatbotBottomSheet extends StatefulWidget {
  const _ChatbotBottomSheet();

  @override
  State<_ChatbotBottomSheet> createState() => _ChatbotBottomSheetState();
}

class _ChatbotBottomSheetState extends State<_ChatbotBottomSheet> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _enviar(String texto) async {
    final clean = texto.trim();
    if (clean.isEmpty) return;

    _inputController.clear();
    final ia = context.read<IaProvider>();
    _scrollToBottom();

    await ia.enviarMensaje(clean);

    if (!mounted) return;
    _scrollToBottom();

    if (ia.errorChat != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ia.errorChat!),
          backgroundColor: Colors.red.shade700,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ia = context.watch<IaProvider>();
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final screenHeight = MediaQuery.of(context).size.height;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 600,
          maxHeight: screenHeight * 0.85,
        ),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.only(bottom: bottomInset),
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.purple.shade700,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        color: Colors.white24,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.auto_awesome, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Asistente SmartLook AI',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'En línea • Pregúntame sobre prendas y reservas',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Reiniciar conversación',
                      icon: const Icon(Icons.refresh, color: Colors.white, size: 20),
                      onPressed: () {
                        ia.limpiarHistorial();
                        _scrollToBottom();
                      },
                    ),
                    IconButton(
                      tooltip: 'Cerrar',
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              // Lista de mensajes
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: ia.mensajes.length + (ia.cargandoMensaje ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == ia.mensajes.length && ia.cargandoMensaje) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Row(
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                color: Colors.purple.shade100,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.auto_awesome, size: 16, color: Colors.purple.shade800),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.purple.shade700,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Escribiendo respuesta...',
                                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    final msg = ia.mensajes[index];
                    return ChatBubble(mensaje: msg);
                  },
                ),
              ),

              // Sugerencias rápidas
              if (ia.sugerencias.isNotEmpty && !ia.cargandoMensaje)
                Container(
                  height: 40,
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: ia.sugerencias.length,
                    separatorBuilder: (context, index) => const SizedBox(width: 8),
                    itemBuilder: (context, i) {
                      final sug = ia.sugerencias[i];
                      return ActionChip(
                        label: Text(sug, style: const TextStyle(fontSize: 12)),
                        backgroundColor: Colors.purple.shade50,
                        side: BorderSide(color: Colors.purple.shade200),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        onPressed: () => _enviar(sug),
                      );
                    },
                  ),
                ),

              const Divider(height: 1),

              // Input row
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _inputController,
                        focusNode: _focusNode,
                        textInputAction: TextInputAction.send,
                        onSubmitted: _enviar,
                        decoration: InputDecoration(
                          hintText: 'Escribí tu consulta...',
                          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          filled: true,
                          fillColor: Colors.grey.shade100,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    CircleAvatar(
                      backgroundColor: Colors.purple.shade700,
                      radius: 22,
                      child: IconButton(
                        icon: const Icon(Icons.send, color: Colors.white, size: 18),
                        onPressed: ia.cargandoMensaje
                            ? null
                            : () => _enviar(_inputController.text),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
