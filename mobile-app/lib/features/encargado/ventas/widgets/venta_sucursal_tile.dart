import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/models/venta.dart';
import '../../../../core/widgets/estado_badge.dart';

class VentaSucursalTile extends StatelessWidget {
  final Venta venta;
  final VoidCallback onTap;

  const VentaSucursalTile({
    super.key,
    required this.venta,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    final fechaStr = dateFormat.format(venta.creadaEn.toLocal());
    final isOnline = venta.canal.toLowerCase() == 'online';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Fila superior: ID de Venta, Canal y Estado
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Text(
                          '#${venta.id}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: isOnline
                              ? Colors.purple.shade50
                              : Colors.teal.shade50,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isOnline ? Icons.language : Icons.store,
                              size: 14,
                              color: isOnline
                                  ? Colors.purple.shade700
                                  : Colors.teal.shade700,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isOnline ? 'Online' : 'Presencial',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isOnline
                                    ? Colors.purple.shade800
                                    : Colors.teal.shade800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  EstadoBadge(estado: venta.estado),
                ],
              ),
              const SizedBox(height: 10),

              // Cliente y Fecha
              Row(
                children: [
                  Icon(Icons.person_outline, size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      venta.nombreCliente != null && venta.nombreCliente!.isNotEmpty
                          ? venta.nombreCliente!
                          : (isOnline ? 'Cliente Web' : 'Cliente Mostrador'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    fechaStr,
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const Divider(height: 18),

              // Fila inferior: Unidades / Items y Monto Total
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.shopping_bag_outlined,
                          size: 15, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Text(
                        '${venta.totalItems} ${venta.totalItems == 1 ? "ítem" : "ítems"} (${venta.totalUnidades} un.)',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Text(
                        '\$${venta.total.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.deepOrange,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(Icons.chevron_right,
                          size: 20, color: Colors.grey.shade400),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
