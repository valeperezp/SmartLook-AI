import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/encargado_provider.dart';
import '../../../core/utils/app_notifications.dart';

class DetalleReservaEncargadoModal extends StatefulWidget {
  final Map<String, dynamic> reserva;

  const DetalleReservaEncargadoModal({
    super.key,
    required this.reserva,
  });

  @override
  State<DetalleReservaEncargadoModal> createState() => _DetalleReservaEncargadoModalState();
}

class _DetalleReservaEncargadoModalState extends State<DetalleReservaEncargadoModal> {
  bool _isSubmitting = false;

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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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

  Future<void> _ejecutarAccion(String nuevoEstado, String tituloAccion) async {
    final reservaId = widget.reserva['id'] as int? ?? 0;

    final mensaje = nuevoEstado == 'cancelada'
        ? '¿Deseas cancelar la Reserva #$reservaId? El stock reservado será liberado a disponible.'
        : '¿Deseas cambiar el estado de la Reserva #$reservaId a "$nuevoEstado"?';

    final confirm = await AppNotifications.confirmar(
      context,
      titulo: '¿$tituloAccion?',
      mensaje: mensaje,
      textoConfirmar: 'Sí, $tituloAccion',
      textoCancelar: 'Volver',
      destructivo: nuevoEstado == 'cancelada',
    );

    if (!confirm || !mounted) return;

    setState(() {
      _isSubmitting = true;
    });

    final provider = context.read<EncargadoProvider>();
    final success = await provider.cambiarEstadoReserva(reservaId, nuevoEstado);

    if (!mounted) return;

    setState(() {
      _isSubmitting = false;
    });

    if (success) {
      Navigator.of(context).pop(true);
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
    final reservaId = widget.reserva['id']?.toString() ?? '-';
    final estado = widget.reserva['estado']?.toString().toLowerCase() ?? 'pendiente';
    final nombreCliente = widget.reserva['nombre_cliente']?.toString() ?? 'Cliente';
    final emailCliente = widget.reserva['email_cliente']?.toString() ?? '-';
    final nombreSucursal = widget.reserva['nombre_sucursal']?.toString() ?? 'Sucursal Centro';
    final horarioAprox = widget.reserva['horario_aproximado']?.toString();

    final fechaRaw = widget.reserva['creada_en']?.toString() ??
        widget.reserva['creado_en']?.toString() ??
        '';
    DateTime? fecha;
    if (fechaRaw.isNotEmpty) {
      fecha = DateTime.tryParse(fechaRaw)?.toLocal();
    }
    final fechaStr = fecha != null
        ? '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year} ${fecha.hour.toString().padLeft(2, '0')}:${fecha.minute.toString().padLeft(2, '0')}'
        : fechaRaw;

    final totalEstimado = (widget.reserva['total_estimado'] as num?)?.toDouble() ?? 0.0;
    final items = widget.reserva['items'] as List<dynamic>? ?? [];

    final esPendiente = estado == 'pendiente';
    final esConfirmada = estado == 'confirmada';
    final sePuedeCancelar = esPendiente || esConfirmada;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header fijo
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
            child: Row(
              children: [
                Text(
                  'Reserva #$reservaId',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 12),
                _buildStatusBadge(estado),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Contenido con scroll
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Info Cliente
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        backgroundColor: Colors.orange.shade50,
                        radius: 20,
                        child: Icon(Icons.person, color: Colors.orange.shade800),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              nombreCliente,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              emailCliente,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Icon(Icons.calendar_today, size: 14, color: Colors.grey.shade600),
                                const SizedBox(width: 4),
                                Text(
                                  'Creada: $fechaStr',
                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                                ),
                              ],
                            ),
                            if (horarioAprox != null && horarioAprox.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(Icons.schedule, size: 14, color: Colors.grey.shade600),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Horario aproximado: $horarioAprox',
                                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Info Sucursal
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.storefront, size: 18, color: Colors.grey.shade700),
                        const SizedBox(width: 8),
                        Text(
                          'Sucursal: ',
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                        ),
                        Text(
                          nombreSucursal,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Tabla de Items
                  const Text(
                    'Artículos reservados',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),

                  if (items.isEmpty)
                    Text(
                      'No hay detalles de artículos disponibles',
                      style: TextStyle(color: Colors.grey.shade600),
                    )
                  else
                    ...items.map((it) {
                      final nomProd = it['nombre_producto']?.toString() ?? 'Producto';
                      final talla = it['nombre_talla']?.toString() ?? '-';
                      final color = it['nombre_color']?.toString() ?? '-';
                      final cant = it['cantidad'] as int? ?? 1;
                      final precio = (it['precio_unitario'] as num?)?.toDouble() ?? 0.0;
                      final subtotal = cant * precio;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        elevation: 1,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(color: Colors.grey.shade200),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: Colors.orange.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Center(
                                  child: Text(
                                    '${cant}x',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.orange.shade900,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      nomProd,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Talla: $talla  •  Color: $color',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '\$${subtotal.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  Text(
                                    '\$${precio.toStringAsFixed(2)} c/u',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade500,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  const SizedBox(height: 16),

                  // Total Estimado
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total Estimado:',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '\$${totalEstimado.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange.shade900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Barra inferior de botones de acción
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: _isSubmitting
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(8.0),
                      child: CircularProgressIndicator(),
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cerrar'),
                      ),
                      if (sePuedeCancelar) ...[
                        const SizedBox(width: 8),
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red.shade700,
                            side: BorderSide(color: Colors.red.shade300),
                          ),
                          onPressed: () => _ejecutarAccion('cancelada', 'Cancelar reserva'),
                          child: const Text('Cancelar'),
                        ),
                      ],
                      if (esPendiente) ...[
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue.shade700,
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(Icons.check, size: 18),
                          label: const Text('Confirmar'),
                          onPressed: () => _ejecutarAccion('confirmada', 'Confirmar reserva'),
                        ),
                      ],
                      if (esConfirmada) ...[
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade700,
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(Icons.done_all, size: 18),
                          label: const Text('Marcar atendida'),
                          onPressed: () => _ejecutarAccion('atendida', 'Marcar atendida'),
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
