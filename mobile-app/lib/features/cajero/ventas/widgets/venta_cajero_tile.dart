import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/models/venta.dart';
import '../../../../core/widgets/estado_badge.dart';

class VentaCajeroTile extends StatelessWidget {
  final Venta venta;
  final VoidCallback onTap;

  const VentaCajeroTile({
    super.key,
    required this.venta,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    final fechaStr = dateFormat.format(venta.creadaEn.toLocal());
    final isPresencial = venta.canal.toLowerCase() == 'presencial';

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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '#${venta.id}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade900,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: isPresencial ? Colors.teal.shade50 : Colors.purple.shade50,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isPresencial ? 'Presencial' : 'Online',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isPresencial ? Colors.teal.shade800 : Colors.purple.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  EstadoBadge(estado: venta.estado),
                ],
              ),
              const SizedBox(height: 10),

              Row(
                children: [
                  Icon(Icons.person_outline, size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      venta.nombreCliente != null && venta.nombreCliente!.isNotEmpty
                          ? venta.nombreCliente!
                          : 'Cliente Mostrador',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    fechaStr,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                ],
              ),
              const Divider(height: 18),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${venta.totalItems} ítems (${venta.totalUnidades} un.)',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
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
                      const SizedBox(width: 4),
                      Icon(Icons.chevron_right, size: 20, color: Colors.grey.shade400),
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
