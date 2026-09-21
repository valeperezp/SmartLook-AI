import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/loading_state.dart';
import '../../../auth/providers/auth_provider.dart';
import '../providers/movimientos_provider.dart';
import '../widgets/movimiento_tile.dart';

class MovimientosScreen extends StatefulWidget {
  const MovimientosScreen({super.key});

  @override
  State<MovimientosScreen> createState() => _MovimientosScreenState();
}

class _MovimientosScreenState extends State<MovimientosScreen> {
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      final sucursalId = auth.usuario?.sucursalId;
      context.read<MovimientosProvider>().cargarMovimientos(sucursalId: sucursalId);
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _seleccionarRangoFechas() async {
    final prov = context.read<MovimientosProvider>();
    final inicial = DateTimeRange(
      start: prov.fechaInicio ?? DateTime.now().subtract(const Duration(days: 30)),
      end: prov.fechaFin ?? DateTime.now(),
    );

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      initialDateRange: inicial,
      helpText: 'Filtrar movimientos por fecha',
      cancelText: 'Limpiar',
      confirmText: 'Aplicar',
    );

    if (picked != null) {
      prov.setRangoFechas(picked.start, picked.end);
    } else {
      prov.setRangoFechas(null, null);
    }
  }

  String _textoRango(DateTime? inicio, DateTime? fin) {
    if (inicio == null || fin == null) return 'Rango de fechas';
    final d1 = '${inicio.day}/${inicio.month}';
    final d2 = '${fin.day}/${fin.month}';
    return '$d1 — $d2';
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final prov = context.watch<MovimientosProvider>();
    final sucursalId = auth.usuario?.sucursalId;
    final movimientos = prov.movimientosFiltrados;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Historial de Movimientos',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.orange.shade900,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.go('/encargado'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'Recargar',
            onPressed: prov.isLoading
                ? null
                : () => prov.cargarMovimientos(sucursalId: sucursalId),
          ),
        ],
      ),
      body: Column(
        children: [
          // Barra de Filtros
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            color: AppTheme.surface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Buscador
                TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Buscar por producto, motivo o usuario...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchCtrl.clear();
                              prov.setBusqueda('');
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  onChanged: (val) => prov.setBusqueda(val),
                ),
                const SizedBox(height: 10),

                // Filtros de Tipo y Fecha
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildTipoChip(prov, 'todos', 'Todos'),
                      const SizedBox(width: 8),
                      _buildTipoChip(prov, 'entrada', 'Entradas ↓'),
                      const SizedBox(width: 8),
                      _buildTipoChip(prov, 'salida', 'Salidas ↑'),
                      const SizedBox(width: 8),
                      _buildTipoChip(prov, 'ajuste', 'Ajustes ⚙'),
                      const SizedBox(width: 8),
                      _buildTipoChip(prov, 'venta', 'Ventas 🛒'),
                      const SizedBox(width: 12),

                      // Botón Filtro Fechas
                      ActionChip(
                        avatar: Icon(
                          Icons.calendar_today,
                          size: 14,
                          color: prov.fechaInicio != null
                              ? Colors.white
                              : AppTheme.primary,
                        ),
                        label: Text(
                          _textoRango(prov.fechaInicio, prov.fechaFin),
                          style: TextStyle(
                            fontSize: 12,
                            color: prov.fechaInicio != null
                                ? Colors.white
                                : AppTheme.textPrimary,
                            fontWeight: prov.fechaInicio != null
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                        backgroundColor: prov.fechaInicio != null
                            ? AppTheme.primary
                            : AppTheme.surface,
                        side: const BorderSide(color: AppTheme.border),
                        onPressed: _seleccionarRangoFechas,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Total y lista
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${movimientos.length} movimientos registrados',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textSecondary,
                  ),
                ),
                if (prov.filtroTipo != 'todos' ||
                    prov.busqueda.isNotEmpty ||
                    prov.fechaInicio != null)
                  GestureDetector(
                    onTap: () {
                      _searchCtrl.clear();
                      prov.limpiarFiltros();
                    },
                    child: const Text(
                      'Limpiar filtros',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Lista de Movimientos
          Expanded(
            child: prov.isLoading && prov.movimientos.isEmpty
                ? const LoadingState(mensaje: 'Cargando movimientos de inventario...')
                : prov.errorMessage != null && prov.movimientos.isEmpty
                    ? EmptyState(
                        icono: Icons.error_outline,
                        titulo: 'Error al cargar',
                        mensaje: prov.errorMessage,
                        onReintentar: () =>
                            prov.cargarMovimientos(sucursalId: sucursalId),
                      )
                    : movimientos.isEmpty
                        ? EmptyState(
                            icono: Icons.swap_horiz,
                            titulo: 'No se encontraron movimientos',
                            mensaje: prov.filtroTipo != 'todos' ||
                                    prov.busqueda.isNotEmpty ||
                                    prov.fechaInicio != null
                                ? 'No hay registros que coincidan con los filtros aplicados.'
                                : 'Aún no se han registrado entradas, salidas ni ajustes.',
                            textoBoton: 'Recargar',
                            onReintentar: () =>
                                prov.cargarMovimientos(sucursalId: sucursalId),
                          )
                        : RefreshIndicator(
                            onRefresh: () =>
                                prov.cargarMovimientos(sucursalId: sucursalId),
                            child: ListView.separated(
                              padding: const EdgeInsets.all(12),
                              itemCount: movimientos.length,
                              separatorBuilder: (context, index) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                return MovimientoTile(
                                  movimiento: movimientos[index],
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildTipoChip(MovimientosProvider prov, String key, String label) {
    final selected = prov.filtroTipo == key;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: Colors.orange.shade800,
      labelStyle: TextStyle(
        fontSize: 12,
        color: selected ? Colors.white : AppTheme.textPrimary,
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
      ),
      onSelected: (val) {
        if (val) prov.setFiltroTipo(key);
      },
    );
  }
}
