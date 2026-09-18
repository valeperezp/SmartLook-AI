import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/encargado_provider.dart';
import '../../../core/utils/app_notifications.dart';

class ModalMovimiento extends StatefulWidget {
  final Map<String, dynamic> inventarioItem;
  final String tipo; // 'entrada' o 'salida'

  const ModalMovimiento({
    super.key,
    required this.inventarioItem,
    required this.tipo,
  });

  @override
  State<ModalMovimiento> createState() => _ModalMovimientoState();
}

class _ModalMovimientoState extends State<ModalMovimiento> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _cantidadController = TextEditingController();
  final TextEditingController _motivoController = TextEditingController();

  bool _isSubmitting = false;

  @override
  void dispose() {
    _cantidadController.dispose();
    _motivoController.dispose();
    super.dispose();
  }

  Future<void> _confirmar() async {
    if (!_formKey.currentState!.validate()) return;

    final cantidad = int.tryParse(_cantidadController.text.trim()) ?? 0;
    final motivo = _motivoController.text.trim();
    final tipoNorm = widget.tipo.toLowerCase();

    setState(() {
      _isSubmitting = true;
    });

    final provider = context.read<EncargadoProvider>();
    final success = await provider.crearMovimiento({
      'inventario_id': widget.inventarioItem['id'],
      'tipo': tipoNorm,
      'cantidad': cantidad,
      'motivo': motivo.isEmpty ? (tipoNorm == 'entrada' ? 'Entrada de mercancía' : 'Salida de mercancía') : motivo,
    });

    if (!mounted) return;

    setState(() {
      _isSubmitting = false;
    });

    if (success) {
      Navigator.of(context).pop(true);
      AppNotifications.success(
        context,
        tipoNorm == 'entrada' ? 'Entrada registrada' : 'Salida registrada',
      );
    } else {
      AppNotifications.error(
        context,
        provider.errorMessage ?? 'Error al registrar movimiento',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEntrada = widget.tipo.toLowerCase() == 'entrada';
    final actionColor = isEntrada ? Colors.green.shade700 : Colors.red.shade700;
    final actionName = isEntrada ? 'entrada' : 'salida';

    final nombreProducto = widget.inventarioItem['nombre_producto']?.toString() ?? 'Producto';
    final nombreTalla = widget.inventarioItem['nombre_talla']?.toString() ?? '-';
    final nombreColor = widget.inventarioItem['nombre_color']?.toString() ?? '-';
    final cantDisponible = widget.inventarioItem['cantidad_disponible'] as int? ?? 0;

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
                    backgroundColor: isEntrada ? Colors.green.shade50 : Colors.red.shade50,
                    child: Icon(
                      isEntrada ? Icons.add_circle : Icons.remove_circle,
                      color: actionColor,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Registrar $actionName',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: actionColor,
                          ),
                        ),
                        Text(
                          '$nombreProducto (Talla: $nombreTalla • Color: $nombreColor)',
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
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.inventory_2_outlined, size: 20, color: Colors.grey.shade700),
                    const SizedBox(width: 8),
                    Text(
                      'Disponible actual: ',
                      style: TextStyle(fontSize: 14, color: Colors.grey.shade800),
                    ),
                    Text(
                      '$cantDisponible unidades',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Campo Cantidad
              Text(
                'Cantidad a registrar *',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.grey.shade800),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _cantidadController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  hintText: isEntrada ? 'Ej: 10' : 'Máximo: $cantDisponible',
                  prefixIcon: const Icon(Icons.numbers),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Ingresa una cantidad';
                  }
                  final n = int.tryParse(val.trim());
                  if (n == null || n < 1) {
                    return 'La cantidad mínima es 1';
                  }
                  if (!isEntrada && n > cantDisponible) {
                    return 'No puedes retirar más de lo disponible ($cantDisponible un.)';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Campo Motivo
              Text(
                'Motivo (opcional)',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.grey.shade800),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _motivoController,
                maxLength: 255,
                decoration: InputDecoration(
                  hintText: isEntrada ? 'Ej: Recepción de proveedor, reposición' : 'Ej: Merma, envío o retiro',
                  prefixIcon: const Icon(Icons.comment_outlined),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
              const SizedBox(height: 12),

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
                      backgroundColor: actionColor,
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
                        : Text('Confirmar $actionName'),
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
