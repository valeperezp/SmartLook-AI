import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../models/movimiento_inventario.dart';

class MovimientoTile extends StatelessWidget {
  final MovimientoInventario movimiento;

  const MovimientoTile({
    super.key,
    required this.movimiento,
  });

  IconData _iconoParaTipo(String tipo) {
    switch (tipo.toLowerCase()) {
      case 'entrada':
        return Icons.arrow_downward;
      case 'salida':
        return Icons.arrow_upward;
      case 'ajuste':
        return Icons.tune;
      case 'venta':
        return Icons.shopping_bag_outlined;
      case 'reserva':
        return Icons.bookmark_outline;
      default:
        return Icons.swap_horiz;
    }
  }

  Color _colorParaTipo(String tipo) {
    switch (tipo.toLowerCase()) {
      case 'entrada':
        return Colors.green.shade700;
      case 'salida':
        return Colors.red.shade700;
      case 'ajuste':
        return Colors.amber.shade800;
      case 'venta':
        return Colors.blue.shade700;
      case 'reserva':
        return Colors.purple.shade700;
      default:
        return Colors.blueGrey.shade700;
    }
  }

  Color _bgParaTipo(String tipo) {
    switch (tipo.toLowerCase()) {
      case 'entrada':
        return Colors.green.shade50;
      case 'salida':
        return Colors.red.shade50;
      case 'ajuste':
        return Colors.amber.shade50;
      case 'venta':
        return Colors.blue.shade50;
      case 'reserva':
        return Colors.purple.shade50;
      default:
        return Colors.blueGrey.shade50;
    }
  }

  String _formatoFecha(DateTime dt) {
    final dia = dt.day.toString().padLeft(2, '0');
    final mes = dt.month.toString().padLeft(2, '0');
    final anio = dt.year;
    final hora = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$dia/$mes/$anio $hora:$min';
  }

  @override
  Widget build(BuildContext context) {
    final color = _colorParaTipo(movimiento.tipo);
    final bgColor = _bgParaTipo(movimiento.tipo);
    final icono = _iconoParaTipo(movimiento.tipo);

    final esPositivo = movimiento.tipo.toLowerCase() == 'entrada';
    final prefijoCantidad = esPositivo ? '+' : (movimiento.tipo.toLowerCase() == 'salida' ? '-' : '');

    return Card(
      color: AppTheme.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        side: const BorderSide(color: AppTheme.border, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar con ícono del tipo
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: bgColor,
                shape: BoxShape.circle,
                border: Border.all(color: color.withValues(alpha: 0.3)),
              ),
              child: Icon(icono, color: color, size: 22),
            ),
            const SizedBox(width: 12),

            // Contenido central: Producto, Motivo, Usuario y Fecha
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          movimiento.nombreProducto ??
                              'Inventario #${movimiento.inventarioId}',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ),
                      // Badge tipo
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: bgColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: color.withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          movimiento.tipo.toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),

                  // Motivo
                  if (movimiento.motivo != null &&
                      movimiento.motivo!.isNotEmpty) ...[
                    Text(
                      movimiento.motivo!,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],

                  // Pie con Usuario y Fecha
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.person_outline,
                              size: 14, color: Colors.grey.shade600),
                          const SizedBox(width: 4),
                          Text(
                            movimiento.nombreUsuario ?? 'Sistema',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.access_time,
                              size: 14, color: Colors.grey.shade600),
                          const SizedBox(width: 4),
                          Text(
                            _formatoFecha(movimiento.creadoEn),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),

            // Cantidad a la derecha
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$prefijoCantidad${movimiento.cantidad}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'unidades',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
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
