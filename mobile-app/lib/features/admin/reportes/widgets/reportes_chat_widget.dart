import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/reportes_chat_provider.dart';

class ReportesChatModal extends StatefulWidget {
  final int? sucursalId;

  const ReportesChatModal({
    super.key,
    this.sucursalId,
  });

  static void mostrar(BuildContext context, {int? sucursalId}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ChangeNotifierProvider(
        create: (_) => ReportesChatProvider(),
        child: ReportesChatModal(sucursalId: sucursalId),
      ),
    );
  }

  @override
  State<ReportesChatModal> createState() => _ReportesChatModalState();
}

class _ReportesChatModalState extends State<ReportesChatModal> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
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

  void _enviar(ReportesChatProvider provider, String texto) {
    if (texto.trim().isEmpty) return;
    _controller.clear();
    provider.enviarMensaje(texto, sucursalId: widget.sucursalId).then((_) {
      _scrollToBottom();
    });
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ReportesChatProvider>();
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
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
              color: Colors.indigo.shade800,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(50),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.auto_awesome, color: Colors.amber, size: 20),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Asistente IA de Reportes',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        'Consultá métricas en lenguaje natural',
                        style: TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          // Lista de Mensajes
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: provider.mensajes.length,
              itemBuilder: (context, index) {
                final msg = provider.mensajes[index];
                final isUser = msg.autor == 'usuario';

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    mainAxisAlignment:
                        isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!isUser) ...[
                        CircleAvatar(
                          radius: 14,
                          backgroundColor: Colors.indigo.shade100,
                          child: Icon(Icons.auto_awesome,
                              size: 14, color: Colors.indigo.shade800),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: isUser
                                ? Colors.indigo.shade700
                                : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(14),
                              topRight: const Radius.circular(14),
                              bottomLeft: Radius.circular(isUser ? 14 : 2),
                              bottomRight: Radius.circular(isUser ? 2 : 14),
                            ),
                          ),
                          child: Text(
                            msg.texto,
                            style: TextStyle(
                              color: isUser ? Colors.white : Colors.black87,
                              fontSize: 14,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ),
                      if (isUser) ...[
                        const SizedBox(width: 8),
                        CircleAvatar(
                          radius: 14,
                          backgroundColor: Colors.grey.shade300,
                          child: const Icon(Icons.person,
                              size: 16, color: Colors.black54),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),

          // Indicador de "Escribiendo..."
          if (provider.enviando)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'La IA está analizando los datos...',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),

          // Sugerencias Rápidas
          if (!provider.enviando && provider.sugerencias.isNotEmpty)
            Container(
              height: 38,
              margin: const EdgeInsets.only(bottom: 6),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: provider.sugerencias.length,
                separatorBuilder: (context, index) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final sug = provider.sugerencias[index];
                  return ActionChip(
                    label: Text(sug, style: const TextStyle(fontSize: 11)),
                    backgroundColor: Colors.indigo.shade50,
                    side: BorderSide(color: Colors.indigo.shade200),
                    onPressed: () => _enviar(provider, sug),
                  );
                },
              ),
            ),

          // Barra de Input
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(15),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (txt) => _enviar(provider, txt),
                    decoration: InputDecoration(
                      hintText: 'Preguntá sobre ventas, inventario...',
                      hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: theme.colorScheme.primary,
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white, size: 18),
                    onPressed: provider.enviando
                        ? null
                        : () => _enviar(provider, _controller.text),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
