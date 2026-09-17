import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/encargado_provider.dart';
import '../widgets/detalle_reserva_encargado_modal.dart';
import '../../../core/utils/app_notifications.dart';

class EncargadoReservasScreen extends StatefulWidget {
  const EncargadoReservasScreen({super.key});

  @override
  State<EncargadoReservasScreen> createState() => _EncargadoReservasScreenState();
}

class _EncargadoReservasScreenState extends State<EncargadoReservasScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<EncargadoProvider>().cargarReservas();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Widget _buildStatusBadge(String estado) {
    Color textColor;
    Color bgColor;
    String label;

    switch (estado.toLowerCase()) {
      case 'pendiente':
        textColor = Colors.orange.shade900;
        bgColor = Colors.orange.shade100;
        label = 'Pendiente';
        break;
      case 'confirmada':
        textColor = Colors.blue.shade800;
        bgColor = Colors.blue.shade100;
        label = 'Confirmada';
        break;
      case 'atendida':
        textColor = Colors.green.shade800;
        bgColor = Colors.green.shade100;
        label = 'Atendida';
        break;
      case 'cancelada':
      default:
        textColor = Colors.grey.shade800;
        bgColor = Colors.grey.shade200;
        label = 'Cancelada';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildKpiChip({
    required String title,
    required int count,
    required Color color,
    required Color bgColor,
    required String filterKey,
    required String currentFilter,
    required VoidCallback onTap,
  }) {
    final isSelected = currentFilter.toLowerCase() == filterKey.toLowerCase();

    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? color : color.withValues(alpha: 0.3),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                count.toString(),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _verDetalle(Map<String, dynamic> reserva) async {
    final provider = context.read<EncargadoProvider>();
    final detalle = await provider.cargarDetalleReserva(reserva['id']) ?? reserva;

    if (!mounted) return;

    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DetalleReservaEncargadoModal(reserva: detalle),
    );
  }

  Future<void> _cambiarEstado(int reservaId, String nuevoEstado, String titulo) async {
    final mensaje = nuevoEstado == 'cancelada'
        ? '¿Deseas cancelar la Reserva #$reservaId? El stock reservado será liberado a disponible.'
        : '¿Deseas cambiar el estado de la Reserva #$reservaId a "$nuevoEstado"?';

    final confirm = await AppNotifications.confirmar(
      context,
      titulo: '¿$titulo?',
      mensaje: mensaje,
      textoConfirmar: 'Sí, $titulo',
      textoCancelar: 'Volver',
      destructivo: nuevoEstado == 'cancelada',
    );

    if (!confirm || !mounted) return;

    final provider = context.read<EncargadoProvider>();
    final success = await provider.cambiarEstadoReserva(reservaId, nuevoEstado);

    if (!mounted) return;

    if (success) {
      final String msg = nuevoEstado == 'confirmada'
          ? 'Reserva #$reservaId confirmada'
          : (nuevoEstado == 'atendida'
              ? 'Reserva #$reservaId marcada como atendida'
              : 'Reserva #$reservaId cancelada');
      AppNotifications.success(context, msg);
    } else {
      AppNotifications.error(
        context,
        provider.errorMessage ?? 'Error al actualizar reserva',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final encargado = context.watch<EncargadoProvider>();
    final reservas = encargado.reservasFiltradas;

    final filtros = [
      {'label': 'Todas', 'key': 'todas'},
      {'label': 'Pendientes', 'key': 'pendientes'},
      {'label': 'Confirmadas', 'key': 'confirmadas'},
      {'label': 'Atendidas', 'key': 'atendidas'},
      {'label': 'Canceladas', 'key': 'canceladas'},
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Reservas de mi sucursal',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.orange.shade800,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.go('/encargado'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            tooltip: 'Cerrar sesión',
            onPressed: () => auth.logout(),
          ),
        ],
      ),
      body: encargado.isLoading && encargado.reservas.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : encargado.errorMessage != null && encargado.reservas.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, size: 56, color: Colors.red),
                        const SizedBox(height: 12),
                        Text(
                          encargado.errorMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 16),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => encargado.cargarReservas(),
                          child: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => encargado.cargarReservas(),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 850),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Fila de KPIs
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                            child: Row(
                              children: [
                                _buildKpiChip(
                                  title: 'Pendientes',
                                  count: encargado.totalPendientes,
                                  color: Colors.orange.shade900,
                                  bgColor: Colors.orange.shade50,
                                  filterKey: 'pendientes',
                                  currentFilter: encargado.filtroReservas,
                                  onTap: () => encargado.setFiltroReservas('pendientes'),
                                ),
                                const SizedBox(width: 8),
                                _buildKpiChip(
                                  title: 'Confirmadas',
                                  count: encargado.totalConfirmadas,
                                  color: Colors.blue.shade900,
                                  bgColor: Colors.blue.shade50,
                                  filterKey: 'confirmadas',
                                  currentFilter: encargado.filtroReservas,
                                  onTap: () => encargado.setFiltroReservas('confirmadas'),
                                ),
                                const SizedBox(width: 8),
                                _buildKpiChip(
                                  title: 'Atendidas',
                                  count: encargado.totalAtendidas,
                                  color: Colors.green.shade900,
                                  bgColor: Colors.green.shade50,
                                  filterKey: 'atendidas',
                                  currentFilter: encargado.filtroReservas,
                                  onTap: () => encargado.setFiltroReservas('atendidas'),
                                ),
                                const SizedBox(width: 8),
                                _buildKpiChip(
                                  title: 'Canceladas',
                                  count: encargado.totalCanceladas,
                                  color: Colors.grey.shade800,
                                  bgColor: Colors.grey.shade200,
                                  filterKey: 'canceladas',
                                  currentFilter: encargado.filtroReservas,
                                  onTap: () => encargado.setFiltroReservas('canceladas'),
                                ),
                              ],
                            ),
                          ),

                          // Campo de búsqueda
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            child: TextField(
                              controller: _searchController,
                              onChanged: (val) => encargado.setBusquedaReservas(val),
                              decoration: InputDecoration(
                                hintText: 'Buscar por cliente, email o #reserva...',
                                prefixIcon: const Icon(Icons.search),
                                suffixIcon: _searchController.text.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear),
                                        onPressed: () {
                                          _searchController.clear();
                                          encargado.setBusquedaReservas('');
                                        },
                                      )
                                    : null,
                                filled: true,
                                fillColor: Colors.grey.shade50,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(color: Colors.grey.shade300),
                                ),
                              ),
                            ),
                          ),

                          // Chips de filtro por estado
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            child: Row(
                              children: filtros.map((f) {
                                final isSelected = encargado.filtroReservas == f['key'];
                                return Padding(
                                  padding: const EdgeInsets.only(right: 8.0),
                                  child: ChoiceChip(
                                    label: Text(f['label']!),
                                    selected: isSelected,
                                    selectedColor: Colors.orange.shade100,
                                    labelStyle: TextStyle(
                                      color: isSelected ? Colors.orange.shade900 : Colors.black87,
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                    ),
                                    onSelected: (selected) {
                                      if (selected) {
                                        encargado.setFiltroReservas(f['key']!);
                                      }
                                    },
                                  ),
                                );
                              }).toList(),
                            ),
                          ),

                          // Contador
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: Text(
                              '${reservas.length} reservas',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                          const Divider(height: 1),

                          // Lista de Reservas
                          Expanded(
                            child: reservas.isEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.calendar_today_outlined, size: 52, color: Colors.grey.shade400),
                                        const SizedBox(height: 12),
                                        Text(
                                          'No hay reservas registradas',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.grey.shade700,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'No se encontraron reservas con los filtros aplicados',
                                          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                                        ),
                                      ],
                                    ),
                                  )
                                : ListView.builder(
                                    padding: const EdgeInsets.all(12),
                                    itemCount: reservas.length,
                                    itemBuilder: (context, index) {
                                      final item = reservas[index];
                                      final reservaId = item['id'] as int? ?? 0;
                                      final estado = item['estado']?.toString().toLowerCase() ?? 'pendiente';
                                      final nombreCliente = item['nombre_cliente']?.toString() ?? 'Cliente';
                                      final emailCliente = item['email_cliente']?.toString() ?? '-';
                                      final totalItems = item['total_items'] as int? ?? 0;
                                      final totalUnidades = item['total_unidades'] as int? ?? 0;
                                      final totalEstimado = (item['total_estimado'] as num?)?.toDouble() ?? 0.0;

                                      final fechaRaw = item['creada_en']?.toString() ??
                                          item['creado_en']?.toString() ??
                                          '';
                                      DateTime? fecha;
                                      if (fechaRaw.isNotEmpty) {
                                        fecha = DateTime.tryParse(fechaRaw)?.toLocal();
                                      }
                                      final fechaStr = fecha != null
                                          ? '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year} ${fecha.hour.toString().padLeft(2, '0')}:${fecha.minute.toString().padLeft(2, '0')}'
                                          : fechaRaw;

                                      final esPendiente = estado == 'pendiente';
                                      final esConfirmada = estado == 'confirmada';
                                      final sePuedeCancelar = esPendiente || esConfirmada;

                                      return Card(
                                        elevation: 1,
                                        margin: const EdgeInsets.only(bottom: 12),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          side: BorderSide(
                                            color: esPendiente
                                                ? Colors.orange.shade200
                                                : (esConfirmada ? Colors.blue.shade200 : Colors.grey.shade200),
                                          ),
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.all(16),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              // Header: Reserva #X + Badge
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Text(
                                                    'Reserva #$reservaId',
                                                    style: const TextStyle(
                                                      fontSize: 16,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                  _buildStatusBadge(estado),
                                                ],
                                              ),
                                              const SizedBox(height: 8),

                                              // Cliente y fecha
                                              Row(
                                                children: [
                                                  Icon(Icons.person_outline, size: 16, color: Colors.grey.shade700),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    nombreCliente,
                                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Expanded(
                                                    child: Text(
                                                      '($emailCliente)',
                                                      overflow: TextOverflow.ellipsis,
                                                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 4),

                                              Row(
                                                children: [
                                                  Icon(Icons.access_time, size: 14, color: Colors.grey.shade500),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    fechaStr,
                                                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 8),

                                              // Items y Total
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Text(
                                                    '$totalItems items / $totalUnidades unidades',
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                      fontWeight: FontWeight.w500,
                                                      color: Colors.blueGrey.shade700,
                                                    ),
                                                  ),
                                                  Text(
                                                    'Total: \$${totalEstimado.toStringAsFixed(2)}',
                                                    style: TextStyle(
                                                      fontSize: 15,
                                                      fontWeight: FontWeight.bold,
                                                      color: Colors.orange.shade900,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 12),
                                              const Divider(height: 1),
                                              const SizedBox(height: 8),

                                              // Botones de acción
                                              Wrap(
                                                spacing: 8,
                                                runSpacing: 6,
                                                alignment: WrapAlignment.end,
                                                children: [
                                                  OutlinedButton.icon(
                                                    style: OutlinedButton.styleFrom(
                                                      foregroundColor: Colors.blueGrey.shade800,
                                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                    ),
                                                    icon: const Icon(Icons.visibility_outlined, size: 16),
                                                    label: const Text('Ver detalle'),
                                                    onPressed: () => _verDetalle(item as Map<String, dynamic>),
                                                  ),
                                                  if (esPendiente)
                                                    ElevatedButton.icon(
                                                      style: ElevatedButton.styleFrom(
                                                        backgroundColor: Colors.blue.shade700,
                                                        foregroundColor: Colors.white,
                                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                      ),
                                                      icon: const Icon(Icons.check, size: 16),
                                                      label: const Text('Confirmar'),
                                                      onPressed: () => _cambiarEstado(
                                                        reservaId,
                                                        'confirmada',
                                                        'Confirmar reserva',
                                                      ),
                                                    ),
                                                  if (esConfirmada)
                                                    ElevatedButton.icon(
                                                      style: ElevatedButton.styleFrom(
                                                        backgroundColor: Colors.green.shade700,
                                                        foregroundColor: Colors.white,
                                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                      ),
                                                      icon: const Icon(Icons.done_all, size: 16),
                                                      label: const Text('Atender'),
                                                      onPressed: () => _cambiarEstado(
                                                        reservaId,
                                                        'atendida',
                                                        'Marcar como atendida',
                                                      ),
                                                    ),
                                                  if (sePuedeCancelar)
                                                    TextButton.icon(
                                                      style: TextButton.styleFrom(
                                                        foregroundColor: Colors.red.shade700,
                                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                      ),
                                                      icon: const Icon(Icons.close, size: 16),
                                                      label: const Text('Cancelar'),
                                                      onPressed: () => _cambiarEstado(
                                                        reservaId,
                                                        'cancelada',
                                                        'Cancelar reserva',
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
    );
  }
}
