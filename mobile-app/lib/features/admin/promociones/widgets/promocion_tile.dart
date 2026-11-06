import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../models/promocion.dart';

class PromocionTile extends StatelessWidget {
  final Promocion promocion;
  final VoidCallback onEditar;
  final VoidCallback onToggleActivo;

  const PromocionTile({
    super.key,
    required this.promocion,
    required this.onEditar,
    required this.onToggleActivo,
  });

  String _formatearFecha(String fechaStr) {
    if (fechaStr.isEmpty) return '';
    try {
      final dt = DateTime.parse(fechaStr);
      final dia = dt.day.toString().padLeft(2, '0');
      final mes = dt.month.toString().padLeft(2, '0');
      final anio = dt.year;
      return '$dia/$mes/$anio';
    } catch (_) {
      return fechaStr.split('T').first;
    }
  }

  @override
  Widget build(BuildContext context) {
    final esPorcentaje = promocion.tipo == 'porcentaje';
    final valorStr = esPorcentaje
        ? '${promocion.valor.toStringAsFixed(0)}%'
        : '\$${promocion.valor.toStringAsFixed(2)}';

    return Card(
      color: AppTheme.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        side: BorderSide(
          color: promocion.activo
              ? AppTheme.border
              : Theme.of(context).colorScheme.outline,
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Fila superior: Nombre + Badge Descuento + Switch Activo
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              promocion.nombre,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: promocion.activo
                                    ? AppTheme.textPrimary
                                    : Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: promocion.activo
                                  ? Colors.red.shade50
                                  : Theme.of(context).colorScheme.outline,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: promocion.activo
                                    ? Colors.red.shade200
                                    : Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                            child: Text(
                              valorStr,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: promocion.activo
                                    ? Colors.red.shade700
                                    : Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (promocion.descripcion != null &&
                          promocion.descripcion!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          promocion.descripcion!,
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // Botón editar
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  color: AppTheme.primary,
                  tooltip: 'Editar',
                  onPressed: onEditar,
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Fechas y productos
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.date_range, size: 15, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(
                      '${_formatearFecha(promocion.fechaInicio)} — ${_formatearFecha(promocion.fechaFin)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.inventory_2_outlined,
                        size: 15, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(
                      promocion.totalProductos > 0
                          ? '${promocion.totalProductos} productos'
                          : 'General (todos)',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const Divider(height: 20),

            // Estado y acción activar/desactivar
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Chip(
                  label: Text(
                    promocion.activo ? 'Activa' : 'Inactiva',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: promocion.activo
                          ? Colors.teal.shade800
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  backgroundColor: promocion.activo
                      ? Colors.teal.shade50
                      : Theme.of(context).colorScheme.outline,
                  side: BorderSide.none,
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
                TextButton.icon(
                  onPressed: onToggleActivo,
                  icon: Icon(
                    promocion.activo
                        ? Icons.pause_circle_outline
                        : Icons.play_circle_outline,
                    size: 18,
                    color: promocion.activo
                        ? Colors.orange.shade800
                        : Colors.teal.shade700,
                  ),
                  label: Text(
                    promocion.activo ? 'Desactivar' : 'Reactivar',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: promocion.activo
                          ? Colors.orange.shade800
                          : Colors.teal.shade700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
