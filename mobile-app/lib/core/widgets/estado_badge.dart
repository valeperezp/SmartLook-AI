import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class EstadoBadge extends StatelessWidget {
  final String estado;
  final String? label;

  const EstadoBadge({
    super.key,
    required this.estado,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    Color color;
    String displayLabel = label ?? estado;

    switch (estado.toLowerCase().trim()) {
      case 'disponible':
        color = AppTheme.success;
        displayLabel = label ?? 'Disponible';
        break;
      case 'activo':
        color = AppTheme.success;
        displayLabel = label ?? 'Activo';
        break;
      case 'confirmada':
        color = AppTheme.success;
        displayLabel = label ?? 'Confirmada';
        break;
      case 'atendida':
        color = AppTheme.success;
        displayLabel = label ?? 'Atendida';
        break;
      case 'bajo':
      case 'stock bajo':
        color = AppTheme.warning;
        displayLabel = label ?? 'Stock bajo';
        break;
      case 'pendiente':
        color = AppTheme.warning;
        displayLabel = label ?? 'Pendiente';
        break;
      case 'agotado':
        color = AppTheme.error;
        displayLabel = label ?? 'Agotado';
        break;
      case 'cancelada':
        color = AppTheme.error;
        displayLabel = label ?? 'Cancelada';
        break;
      case 'reembolso_pendiente':
        color = AppTheme.warning;
        displayLabel = label ?? 'Reembolso pendiente';
        break;
      case 'reembolsada':
        color = AppTheme.textMuted;
        displayLabel = label ?? 'Reembolsada';
        break;
      case 'inactivo':
        color = AppTheme.textMuted;
        displayLabel = label ?? 'Inactivo';
        break;
      default:
        color = AppTheme.primary;
        break;
    }

    // Los colores del tema oscuro son claros: sobre una hoja clara el texto se oscurece para que se lea.
    final colorTexto = Theme.of(context).brightness == Brightness.light
        ? HSLColor.fromColor(color).withLightness(0.28).toColor()
        : color;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
      ),
      child: Text(
        displayLabel,
        style: TextStyle(
          color: colorTexto,
          fontWeight: FontWeight.w600,
          fontSize: 11,
        ),
      ),
    );
  }
}
