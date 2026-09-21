import 'package:flutter/material.dart';
import '../models/item_carrito_pos.dart';

class CarritoPosWidget extends StatelessWidget {
  final List<ItemCarritoPos> items;
  final double total;
  final int unidades;
  final Function(int index, int delta) onActualizarCantidad;
  final Function(int index) onEliminarItem;
  final VoidCallback onVaciar;
  final VoidCallback onCobrar;
  final bool isProcesando;

  const CarritoPosWidget({
    super.key,
    required this.items,
    required this.total,
    required this.unidades,
    required this.onActualizarCantidad,
    required this.onEliminarItem,
    required this.onVaciar,
    required this.onCobrar,
    this.isProcesando = false,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.shopping_cart_outlined, size: 54, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              const Text(
                'Carrito POS vacío',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                'Buscá prendas y pulsa "Agregar" para armar la venta presencial.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        // Header del Carrito POS
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.point_of_sale, size: 20, color: Colors.blue),
                  const SizedBox(width: 8),
                  Text(
                    'Ticket Actual ($unidades un.)',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ],
              ),
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
                icon: const Icon(Icons.delete_sweep, size: 18),
                label: const Text('Vaciar', style: TextStyle(fontSize: 12)),
                onPressed: onVaciar,
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // Lista de ítems
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            separatorBuilder: (_, index) => const Divider(height: 12),
            itemBuilder: (context, index) {
              final item = items[index];
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Info de la prenda
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
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${item.nombreTalla != null ? "Talla: ${item.nombreTalla} | " : ""}${item.nombreColor != null ? "Color: ${item.nombreColor} | " : ""}\$${item.precio.toStringAsFixed(2)} c/u',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),

                  // Controles de cantidad (- 1 +)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline, size: 20),
                        color: Colors.grey.shade700,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => onActualizarCantidad(index, -1),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          '${item.cantidad}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline, size: 20),
                        color: Colors.blue.shade700,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => onActualizarCantidad(index, 1),
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),

                  // Subtotal
                  Text(
                    '\$${item.subtotal.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),

                  // Botón eliminar
                  IconButton(
                    icon: const Icon(Icons.close, size: 18, color: Colors.grey),
                    onPressed: () => onEliminarItem(index),
                  ),
                ],
              );
            },
          ),
        ),

        // Barra inferior con Total y Botón Cobrar
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                offset: const Offset(0, -3),
                blurRadius: 6,
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'TOTAL A COBRAR:',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '\$${total.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.deepOrange,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade600,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    icon: isProcesando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.payments),
                    label: Text(
                      isProcesando
                          ? 'Procesando Venta...'
                          : 'COBRAR \$${total.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    onPressed: isProcesando ? null : onCobrar,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
