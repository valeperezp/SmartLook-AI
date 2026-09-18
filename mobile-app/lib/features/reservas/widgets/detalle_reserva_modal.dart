import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/models/reserva.dart';

class DetalleReservaModal extends StatelessWidget {
  final Reserva reserva;

  const DetalleReservaModal({
    super.key,
    required this.reserva,
  });

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
        textColor = Colors.blue.shade900;
        bgColor = Colors.blue.shade100;
        label = 'Confirmada';
        break;
      case 'atendida':
        textColor = Colors.green.shade900;
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
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final fechaFormat = DateFormat('dd/MM/yyyy HH:mm');

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 600,
          maxHeight: MediaQuery.of(context).size.height * 0.90,
        ),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.all(20.0),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Reserva #${reserva.id}',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            reserva.nombreSucursal ?? 'Sucursal principal',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      _buildStatusBadge(reserva.estado),
                    ],
                  ),
                  const Divider(height: 24),

                  // 2. Info General
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (reserva.nombreCliente != null) ...[
                          Row(
                            children: [
                              const Icon(Icons.person_outline,
                                  size: 16, color: Colors.grey),
                              const SizedBox(width: 8),
                              Text('Cliente: ${reserva.nombreCliente!}'),
                            ],
                          ),
                          const SizedBox(height: 6),
                        ],
                        if (reserva.emailCliente != null) ...[
                          Row(
                            children: [
                              const Icon(Icons.email_outlined,
                                  size: 16, color: Colors.grey),
                              const SizedBox(width: 8),
                              Text('Email: ${reserva.emailCliente!}'),
                            ],
                          ),
                          const SizedBox(height: 6),
                        ],
                        Row(
                          children: [
                            const Icon(Icons.access_time,
                                size: 16, color: Colors.grey),
                            const SizedBox(width: 8),
                            Text('Creada: ${fechaFormat.format(reserva.creadaEn)}'),
                          ],
                        ),
                        if (reserva.horarioAproximado != null) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.calendar_today,
                                  size: 16, color: Colors.blue),
                              const SizedBox(width: 8),
                              Text(
                                'Horario estimado: ${fechaFormat.format(reserva.horarioAproximado!)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Colors.blue,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // 3. Lista de Items
                  const Text(
                    'Prendas reservadas',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),

                  ...reserva.items.map((item) {
                    final subtotal = item.cantidad * item.precioUnitario;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.checkroom,
                                  size: 24, color: Colors.blue),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.nombreProducto,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Talla: ${item.nombreTalla ?? "-"}  |  Color: ${item.nombreColor ?? "-"}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${item.cantidad} x \$${item.precioUnitario.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '\$${subtotal.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: primaryColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),

                  const SizedBox(height: 14),

                  // 4. Total estimado
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Total Estimado (${reserva.totalUnidades} prendas):',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '\$${reserva.totalEstimado.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: primaryColor,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // 5. Botón Cerrar
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('Cerrar', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
