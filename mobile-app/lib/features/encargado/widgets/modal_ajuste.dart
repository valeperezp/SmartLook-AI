import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/encargado_provider.dart';
import '../../../core/utils/app_notifications.dart';

class ModalAjuste extends StatefulWidget {
  final Map<String, dynamic> inventarioItem;

  const ModalAjuste({
    super.key,
    required this.inventarioItem,
  });

  @override
  State<ModalAjuste> createState() => _ModalAjusteState();
}

class _ModalAjusteState extends State<ModalAjuste> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _cantidadController = TextEditingController();
  final TextEditingController _motivoController = TextEditingController();

  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    // Pre-poblar con la cantidad disponible actual
    final cantActual = widget.inventarioItem['cantidad_disponible']?.toString() ?? '0';
    _cantidadController.text = cantActual;
  }

  @override
  void dispose() {
    _cantidadController.dispose();
    _motivoController.dispose();
    super.dispose();
  }

  Future<void> _confirmar() async {
    if (!_formKey.currentState!.validate()) return;

    final nuevaCantidad = int.tryParse(_cantidadController.text.trim()) ?? 0;
    final motivo = _motivoController.text.trim();

    setState(() {
      _isSubmitting = true;
    });

    final provider = context.read<EncargadoProvider>();
    final success = await provider.crearAjuste({
      'inventario_id': widget.inventarioItem['id'],
      'nueva_cantidad': nuevaCantidad,
      'cantidad': nuevaCantidad,
      'motivo': motivo.isEmpty ? 'Ajuste por conteo físico / auditoría' : motivo,
    });

    if (!mounted) return;

    setState(() {
      _isSubmitting = false;
    });

    if (success) {
      Navigator.of(context).pop(true);
      AppNotifications.success(context, 'Ajuste aplicado');
    } else {
      AppNotifications.error(
        context,
        provider.errorMessage ?? 'Error al aplicar ajuste de stock',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
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
                    backgroundColor: Colors.blue.shade50,
                    child: Icon(Icons.tune, color: Colors.blue.shade700, size: 26),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ajuste de stock',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade800,
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

              // Campo Nueva cantidad real
              Text(
                'Nueva cantidad real (conteo físico) *',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.grey.shade800),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _cantidadController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  hintText: 'Ej: 15',
                  prefixIcon: const Icon(Icons.pin_outlined),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Ingresa la nueva cantidad real';
                  }
                  final n = int.tryParse(val.trim());
                  if (n == null || n < 0) {
                    return 'La cantidad no puede ser negativa';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Campo Motivo
              Text(
                'Motivo del ajuste (opcional)',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.grey.shade800),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _motivoController,
                maxLength: 255,
                decoration: InputDecoration(
                  hintText: 'Ej: Conteo físico mensual, merma o daño',
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
                      backgroundColor: Colors.blue.shade700,
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
                        : const Text('Aplicar ajuste'),
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
