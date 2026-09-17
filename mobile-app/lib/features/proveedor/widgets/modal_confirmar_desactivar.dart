import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class ModalConfirmarDesactivar extends StatelessWidget {
  final String nombreProducto;
  final bool esReactivar;
  final VoidCallback onConfirm;

  const ModalConfirmarDesactivar({
    super.key,
    required this.nombreProducto,
    this.esReactivar = false,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final accion = esReactivar ? 'reactivado' : 'desactivado';
    final titulo = esReactivar ? '¿Reactivar producto?' : '¿Desactivar producto?';
    final btnColor = esReactivar ? AppTheme.success : AppTheme.error;

    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      title: Row(
        children: [
          Icon(
            esReactivar ? Icons.refresh : Icons.warning_amber_rounded,
            color: btnColor,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              titulo,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ),
        ],
      ),
      content: Text(
        'El producto \'$nombreProducto\' será $accion.',
        style: const TextStyle(fontSize: 15),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: btnColor,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onPressed: () {
            Navigator.of(context).pop();
            onConfirm();
          },
          child: const Text('Confirmar'),
        ),
      ],
    );
  }
}
