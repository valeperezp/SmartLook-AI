import 'package:flutter/material.dart';
import '../models/carrito_item.dart';

class CarritoItemTile extends StatelessWidget {
  final CarritoItem item;
  final int index;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onDelete;

  const CarritoItemTile({
    super.key,
    required this.item,
    required this.index,
    required this.onIncrement,
    required this.onDecrement,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final maxAlcanzado =
        item.maxDisponible != null && item.cantidad >= item.maxDisponible!;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 0.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Imagen o icono
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: item.imagenUrl != null && item.imagenUrl!.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(
                            item.imagenUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => Icon(
                              Icons.checkroom,
                              color: primaryColor,
                              size: 28,
                            ),
                          ),
                        )
                      : Icon(
                          Icons.checkroom,
                          color: primaryColor,
                          size: 28,
                        ),
                ),
                const SizedBox(width: 12),
                // Detalles
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.nombreProducto,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (item.nombreTalla != null &&
                              item.nombreTalla!.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(4),
                                border:
                                    Border.all(color: Colors.grey.shade300),
                              ),
                              child: Text(
                                'Talla: ${item.nombreTalla}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade800,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          if (item.nombreColor != null &&
                              item.nombreColor!.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(4),
                                border:
                                    Border.all(color: Colors.grey.shade300),
                              ),
                              child: Text(
                                'Color: ${item.nombreColor}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade800,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '\$${item.precio.toStringAsFixed(2)} c/u',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                // Botón eliminar
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  color: Colors.grey.shade500,
                  splashRadius: 18,
                  onPressed: onDelete,
                  tooltip: 'Quitar del carrito',
                ),
              ],
            ),
            const Divider(height: 18),
            // Fila inferior: Stepper + Subtotal
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Stepper
                Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        children: [
                          InkWell(
                            onTap: onDecrement,
                            borderRadius: const BorderRadius.horizontal(
                                left: Radius.circular(8)),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              child: Icon(
                                item.cantidad == 1
                                    ? Icons.delete_outline
                                    : Icons.remove,
                                size: 16,
                                color: item.cantidad == 1
                                    ? Colors.red.shade700
                                    : Colors.black87,
                              ),
                            ),
                          ),
                          Container(
                            constraints: const BoxConstraints(minWidth: 32),
                            alignment: Alignment.center,
                            child: Text(
                              '${item.cantidad}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          InkWell(
                            onTap: maxAlcanzado ? null : onIncrement,
                            borderRadius: const BorderRadius.horizontal(
                                right: Radius.circular(8)),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              child: Icon(
                                Icons.add,
                                size: 16,
                                color: maxAlcanzado
                                    ? Colors.grey.shade400
                                    : Colors.black87,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (maxAlcanzado) ...[
                      const SizedBox(width: 8),
                      Text(
                        'Máx stock',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.orange.shade800,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
                // Subtotal
                Text(
                  '\$${item.subtotal.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: primaryColor,
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
