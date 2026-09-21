import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../models/reporte_models.dart';

class GraficoTorta extends StatelessWidget {
  final List<ReservasPorEstado> datos;
  final String titulo;

  const GraficoTorta({
    super.key,
    required this.datos,
    this.titulo = 'Reservas por estado',
  });

  Color _colorParaEstado(String estado) {
    switch (estado.toLowerCase()) {
      case 'confirmada':
      case 'completada':
        return Colors.teal.shade600;
      case 'pendiente':
        return Colors.amber.shade700;
      case 'en_preparacion':
        return Colors.blue.shade600;
      case 'cancelada':
        return Colors.red.shade600;
      case 'vencida':
      case 'expirada':
        return Colors.blueGrey.shade600;
      default:
        return Colors.purple.shade600;
    }
  }

  String _labelEstado(String estado) {
    switch (estado.toLowerCase()) {
      case 'confirmada':
        return 'Confirmada';
      case 'completada':
        return 'Completada';
      case 'pendiente':
        return 'Pendiente';
      case 'en_preparacion':
        return 'En Prep.';
      case 'cancelada':
        return 'Cancelada';
      case 'vencida':
        return 'Vencida';
      default:
        return estado[0].toUpperCase() + estado.substring(1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final datosValidos = datos.where((d) => d.cantidad > 0).toList();
    final total = datosValidos.fold<int>(0, (acc, e) => acc + e.cantidad);

    if (datosValidos.isEmpty || total == 0) {
      return Card(
        color: AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          side: const BorderSide(color: AppTheme.border, width: 1),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.pie_chart_outline, size: 48, color: Colors.grey.shade400),
                const SizedBox(height: 8),
                Text(
                  'No hay estados registrados actualmente',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Card(
      color: AppTheme.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        side: const BorderSide(color: AppTheme.border, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              titulo,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Distribución de $total reservas totales',
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 180,
              child: PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 40,
                  sections: datosValidos.map((item) {
                    final color = _colorParaEstado(item.estado);
                    final porcentaje = ((item.cantidad / total) * 100).toStringAsFixed(1);
                    return PieChartSectionData(
                      color: color,
                      value: item.cantidad.toDouble(),
                      title: '$porcentaje%',
                      radius: 46,
                      titleStyle: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Leyenda
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: datosValidos.map((item) {
                final color = _colorParaEstado(item.estado);
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${_labelEstado(item.estado)}: ${item.cantidad}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}
