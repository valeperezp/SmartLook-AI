import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/loading_state.dart';
import '../providers/reportes_provider.dart';
import '../widgets/grafico_barras.dart';
import '../widgets/grafico_torta.dart';
import '../widgets/kpi_card.dart';

class ReportesScreen extends StatefulWidget {
  const ReportesScreen({super.key});

  @override
  State<ReportesScreen> createState() => _ReportesScreenState();
}

class _ReportesScreenState extends State<ReportesScreen> {
  List<Map<String, dynamic>> _sucursales = [];
  bool _cargandoSucursales = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ReportesProvider>().cargarReportes();
      _cargarSucursales();
    });
  }

  Future<void> _cargarSucursales() async {
    setState(() => _cargandoSucursales = true);
    try {
      final res = await DioClient().get('/sucursales');
      final list = (res.data as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
      if (mounted) {
        setState(() {
          _sucursales = list;
          _cargandoSucursales = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _cargandoSucursales = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<ReportesProvider>();
    final resumen = prov.resumen;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Reportes y Métricas',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.indigo.shade800,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.go('/admin'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'Recargar datos',
            onPressed: prov.isLoading ? null : () => prov.cargarReportes(),
          ),
        ],
      ),
      body: prov.isLoading && resumen == null
          ? const LoadingState(mensaje: 'Cargando métricas y reportes...')
          : prov.errorMessage != null && resumen == null
              ? EmptyState(
                  icono: Icons.error_outline,
                  titulo: 'Error al cargar reportes',
                  mensaje: prov.errorMessage,
                  onReintentar: () => prov.cargarReportes(),
                )
              : RefreshIndicator(
                  onRefresh: () => prov.cargarReportes(),
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16.0),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 960),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Barra de Filtros
                            _buildFiltrosBar(prov),
                            const SizedBox(height: 20),

                            // Grid de KPIs principales
                            _buildKpisGrid(resumen),
                            const SizedBox(height: 24),

                            // Gráficos
                            LayoutBuilder(
                              builder: (context, constraints) {
                                if (constraints.maxWidth > 700) {
                                  return Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        flex: 6,
                                        child: GraficoBarras(
                                          datos: prov.reservasPorDia,
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        flex: 4,
                                        child: GraficoTorta(
                                          datos: prov.reservasPorEstado,
                                        ),
                                      ),
                                    ],
                                  );
                                }
                                return Column(
                                  children: [
                                    GraficoBarras(datos: prov.reservasPorDia),
                                    const SizedBox(height: 16),
                                    GraficoTorta(datos: prov.reservasPorEstado),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 24),

                            // Comparativa por Sucursales (si hay datos)
                            if (prov.reservasPorSucursal.isNotEmpty)
                              _buildSucursalesCard(prov.reservasPorSucursal),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
    );
  }

  Widget _buildFiltrosBar(ReportesProvider prov) {
    return Card(
      color: AppTheme.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        side: const BorderSide(color: AppTheme.border, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Filtros de consulta',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // Selector de sucursal
                SizedBox(
                  width: 240,
                  child: DropdownButtonFormField<int?>(
                    initialValue: prov.sucursalSeleccionadaId,
                    decoration: InputDecoration(
                      labelText: 'Sucursal',
                      prefixIcon: const Icon(Icons.storefront, size: 20),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('Todas las sucursales'),
                      ),
                      ..._sucursales.map(
                        (s) => DropdownMenuItem<int?>(
                          value: s['id'] as int?,
                          child: Text(
                            s['nombre']?.toString() ?? 'Sucursal ${s['id']}',
                          ),
                        ),
                      ),
                    ],
                    onChanged: _cargandoSucursales
                        ? null
                        : (val) => prov.cambiarSucursal(val),
                  ),
                ),

                // Selector de rango en días
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Período: ',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    _buildFiltroChip(prov, 7, '7d'),
                    const SizedBox(width: 6),
                    _buildFiltroChip(prov, 14, '14d'),
                    const SizedBox(width: 6),
                    _buildFiltroChip(prov, 30, '30d'),
                    const SizedBox(width: 6),
                    _buildFiltroChip(prov, 60, '60d'),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFiltroChip(ReportesProvider prov, int dias, String label) {
    final selected = prov.diasFiltro == dias;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: AppTheme.primary,
      labelStyle: TextStyle(
        color: selected ? Colors.white : AppTheme.textPrimary,
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
        fontSize: 12,
      ),
      onSelected: (val) {
        if (val) {
          prov.cambiarDias(dias);
        }
      },
    );
  }

  Widget _buildKpisGrid(dynamic resumen) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 750
            ? 3
            : constraints.maxWidth > 480
                ? 2
                : 1;

        return GridView.count(
          crossAxisCount: crossAxisCount,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.6,
          children: [
            KpiCard(
              label: 'Total Reservas',
              valor: resumen?.totalReservas.toString() ?? '0',
              icono: Icons.bookmark_added,
              color: Colors.indigo.shade700,
            ),
            KpiCard(
              label: 'Unidades Reservadas',
              valor: resumen?.totalUnidadesReservadas.toString() ?? '0',
              icono: Icons.shopping_basket,
              color: Colors.blue.shade700,
            ),
            KpiCard(
              label: 'Inventario Disponible',
              valor: resumen?.inventarioDisponible.toString() ?? '0',
              icono: Icons.inventory_2,
              color: Colors.green.shade700,
            ),
            KpiCard(
              label: 'Inventario Reservado',
              valor: resumen?.inventarioReservado.toString() ?? '0',
              icono: Icons.lock_clock,
              color: Colors.orange.shade800,
            ),
            KpiCard(
              label: 'Stock Bajo',
              valor: resumen?.productosStockBajo.toString() ?? '0',
              icono: Icons.warning_amber_rounded,
              color: Colors.amber.shade800,
            ),
            KpiCard(
              label: 'Productos Agotados',
              valor: resumen?.productosAgotados.toString() ?? '0',
              icono: Icons.error_outline,
              color: Colors.red.shade700,
            ),
          ],
        );
      },
    );
  }

  Widget _buildSucursalesCard(dynamic sucursales) {
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
            const Text(
              'Comparativa por Sucursales',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Distribución de reservas y unidades por sucursal',
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: sucursales.length,
              separatorBuilder: (context, index) => const Divider(),
              itemBuilder: (context, index) {
                final s = sucursales[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: Colors.indigo.shade50,
                    child: Icon(Icons.storefront, color: Colors.indigo.shade800),
                  ),
                  title: Text(
                    s.nombreSucursal,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text('ID Sucursal: ${s.sucursalId}'),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${s.cantidadReservas} reservas',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primary,
                        ),
                      ),
                      Text(
                        '${s.totalUnidades} prendas',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
