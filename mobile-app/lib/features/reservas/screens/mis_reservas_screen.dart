import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../core/models/reserva.dart';
import '../../../core/utils/app_notifications.dart';
import '../../../core/widgets/estado_badge.dart';
import '../providers/reservas_provider.dart';
import '../widgets/detalle_reserva_modal.dart';

class MisReservasScreen extends StatefulWidget {
  const MisReservasScreen({super.key});

  @override
  State<MisReservasScreen> createState() => _MisReservasScreenState();
}

class _MisReservasScreenState extends State<MisReservasScreen> {
  final DateFormat _dateFormat = DateFormat('dd/MM/yyyy HH:mm');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ReservasProvider>().cargarMisReservas();
    });
  }


  void _verDetalle(BuildContext context, Reserva reserva) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DetalleReservaModal(reserva: reserva),
    );
  }

  Future<void> _confirmarCancelar(Reserva reserva) async {
    final confirmar = await AppNotifications.confirmar(
      context,
      titulo: '¿Cancelar reserva?',
      mensaje:
          '¿Estás seguro de que deseas cancelar la Reserva #${reserva.id}? El stock reservado será liberado.',
      textoConfirmar: 'Sí, cancelar',
      textoCancelar: 'No, mantener',
      destructivo: true,
    );

    if (!confirmar || !mounted) return;

    final provider = context.read<ReservasProvider>();
    final ok = await provider.cancelarReserva(reserva.id);

    if (!mounted) return;

    if (ok) {
      AppNotifications.success(context, 'Reserva #${reserva.id} cancelada');
    } else {
      AppNotifications.error(
        context,
        provider.errorMessage ?? 'Error al cancelar la reserva',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.receipt_long, color: Colors.white),
            SizedBox(width: 8),
            Text(
              'Mis Reservas',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ],
        ),
        backgroundColor: Colors.blue.shade700,
      ),
      body: Consumer<ReservasProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading && provider.reservas.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.errorMessage != null && provider.reservas.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline,
                        size: 56, color: Colors.red),
                    const SizedBox(height: 12),
                    Text(
                      provider.errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => provider.cargarMisReservas(),
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            );
          }

          if (provider.reservas.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.receipt_long_outlined,
                      size: 72,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'No tenés reservas todavía',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Explorá el catálogo y reservá tus prendas favoritas.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: () => context.go('/'),
                      icon: const Icon(Icons.storefront),
                      label: const Text('Explorar catálogo'),
                    ),
                  ],
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () => provider.cargarMisReservas(),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 700),
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: provider.reservas.length,
                  itemBuilder: (context, index) {
                    final reserva = provider.reservas[index];

                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header: Reserva #X + Badge
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Reserva #${reserva.id}',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                EstadoBadge(estado: reserva.estado),
                              ],
                            ),
                            const Divider(height: 20),

                            // Detalles
                            Row(
                              children: [
                                const Icon(Icons.storefront,
                                    size: 16, color: Colors.blue),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Sucursal: ${reserva.nombreSucursal ?? "Principal"}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w500),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(Icons.calendar_today,
                                    size: 16, color: Colors.grey),
                                const SizedBox(width: 8),
                                Text(
                                  'Creada: ${_dateFormat.format(reserva.creadaEn)}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(Icons.inventory_2_outlined,
                                    size: 16, color: Colors.grey),
                                const SizedBox(width: 8),
                                Text(
                                  'Items: ${reserva.totalItems}  |  Unidades: ${reserva.totalUnidades}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),

                            // Total
                            Text(
                              'Total: \$${reserva.totalEstimado.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            const SizedBox(height: 12),

                            // Botones de acción
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                if (reserva.isPendiente) ...[
                                  OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.red.shade700,
                                      side: BorderSide(
                                          color: Colors.red.shade300),
                                    ),
                                    onPressed: () =>
                                        _confirmarCancelar(reserva),
                                    child: const Text('Cancelar'),
                                  ),
                                  const SizedBox(width: 10),
                                ],
                                ElevatedButton(
                                  onPressed: () =>
                                      _verDetalle(context, reserva),
                                  child: const Text('Ver detalle'),
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
            ),
          );
        },
      ),
    );
  }
}
