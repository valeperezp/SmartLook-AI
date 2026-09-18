import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/encargado_provider.dart';
import '../../../core/utils/app_notifications.dart';

class ModalStockMinimo extends StatefulWidget {
  final Map<String, dynamic> inventarioItem;

  const ModalStockMinimo({
    super.key,
    required this.inventarioItem,
  });

  @override
  State<ModalStockMinimo> createState() => _ModalStockMinimoState();
}

class _ModalStockMinimoState extends State<ModalStockMinimo> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _stockMinimoController = TextEditingController();

  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final stockMinActual = widget.inventarioItem['stock_minimo']?.toString() ?? '5';
    _stockMinimoController.text = stockMinActual;
  }

  @override
  void dispose() {
    _stockMinimoController.dispose();
    super.dispose();
  }

  Future<void> _confirmar() async {
    if (!_formKey.currentState!.validate()) return;

    final stockMinimo = int.tryParse(_stockMinimoController.text.trim()) ?? 0;

    setState(() {
      _isSubmitting = true;
    });

    final provider = context.read<EncargadoProvider>();
    final success = await provider.actualizarStockMinimo(
      widget.inventarioItem['id'],
      stockMinimo,
    );

    if (!mounted) return;

    setState(() {
      _isSubmitting = false;
    });

    if (success) {
      Navigator.of(context).pop(true);
      AppNotifications.success(context, 'Stock mínimo actualizado');
    } else {
      AppNotifications.error(
        context,
        provider.errorMessage ?? 'Error al actualizar stock mínimo',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final nombreProducto = widget.inventarioItem['nombre_producto']?.toString() ?? 'Producto';
    final stockMinimoActual = widget.inventarioItem['stock_minimo'] as int? ?? 5;

    return SingleChildScrollView(
      child: Container(
        padding: const EdgeInsets.all(20.0),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.orange.shade50,
                    child: Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800, size: 26),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Stock mínimo',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange.shade900,
                          ),
                        ),
                        Text(
                          nombreProducto,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const Divider(height: 24),

              // Info actual
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.tune, size: 20, color: Colors.orange.shade800),
                    const SizedBox(width: 8),
                    Text(
                      'Stock mínimo actual: ',
                      style: TextStyle(fontSize: 14, color: Colors.orange.shade900),
                    ),
                    Text(
                      '$stockMinimoActual unidades',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.orange.shade900),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Campo Nuevo stock mínimo
              Text(
                'Nuevo stock mínimo *',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.grey.shade800),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _stockMinimoController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  hintText: 'Ej: 8',
                  prefixIcon: const Icon(Icons.warning_amber_outlined),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Ingresa un valor para el stock mínimo';
                  }
                  final n = int.tryParse(val.trim());
                  if (n == null || n < 0) {
                    return 'El stock mínimo no puede ser negativo';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // Explicación
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Cuando el stock baje de este valor, se mostrará una alerta en el panel.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Botones de acción
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange.shade800,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: _isSubmitting ? null : _confirmar,
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Actualizar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
