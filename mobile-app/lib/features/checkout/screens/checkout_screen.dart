import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../carrito/providers/carrito_provider.dart';
import '../providers/checkout_provider.dart';
import '../widgets/qr_payment_widget.dart';
import '../widgets/tarjeta_form.dart';

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final checkout = context.read<CheckoutProvider>();
      checkout.cargarSucursales();
    });
  }

  void _onFinalizado(BuildContext context, {required bool esQR}) {
    final carrito = context.read<CarritoProvider>();
    carrito.vaciar();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final carrito = context.watch<CarritoProvider>();
    final checkout = context.watch<CheckoutProvider>();

    // 1. Pantalla de Éxito / Finalizado
    if (checkout.estado == EstadoCheckout.exitoso) {
      final ordenId = checkout.ordenFinalizadaId ?? checkout.ventaId ?? 0;
      final esQR = checkout.pagoQREnviado;

      return Scaffold(
        appBar: AppBar(
          title: Text(esQR ? 'Pago en Revisión' : '¡Compra Confirmada!'),
          centerTitle: true,
          automaticallyImplyLeading: false,
          backgroundColor: Colors.blue.shade700, // mismo azul que el resto del flujo del cliente
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      color: esQR ? Colors.purple.shade50 : Colors.green.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      esQR ? Icons.hourglass_top_rounded : Icons.check_circle_outline_rounded,
                      size: 54,
                      color: esQR ? Colors.purple.shade700 : Colors.green.shade700,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    esQR ? '¡Comprobante Recibido!' : '¡Pago Procesado con Éxito!',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Theme.of(context).colorScheme.outline),
                    ),
                    child: Text(
                      'Orden #$ordenId',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    esQR
                        ? 'Tu comprobante de pago fue recibido correctamente. El encargado de la sucursal verificará la transferencia y preparará tus prendas.'
                        : 'Tu pago fue confirmado por la pasarela. Ya estamos preparando tu orden para retiro.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () {
                        checkout.reset();
                        context.go('/mis-compras');
                      },
                      icon: const Icon(Icons.shopping_bag_outlined),
                      label: const Text('Ver mis compras', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        checkout.reset();
                        context.go('/');
                      },
                      icon: const Icon(Icons.storefront_outlined),
                      label: const Text('Volver al catálogo'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // 2. Si el carrito está vacío y no hay orden en curso
    if (carrito.estaVacio && checkout.ventaId == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Checkout'),
          backgroundColor: Colors.blue.shade700,
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.remove_shopping_cart_outlined, size: 70, color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(height: 16),
                const Text('Tu carrito está vacío', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(
                  'Agregá productos antes de iniciar el proceso de checkout.',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () => context.go('/'),
                  icon: const Icon(Icons.shopping_bag_outlined),
                  label: const Text('Explorar catálogo'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Finalizar Compra'),
        backgroundColor: Colors.blue.shade700, // mismo azul que el resto del flujo del cliente
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // PASO 1: SUCURSAL
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Theme.of(context).colorScheme.outline),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 14,
                              backgroundColor: theme.colorScheme.primary,
                              child: const Text('1', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                            ),
                            const SizedBox(width: 10),
                            const Text(
                              'Sucursal de retiro / preparación',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (checkout.cargandoSucursales)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.all(12.0),
                              child: CircularProgressIndicator(),
                            ),
                          )
                        else if (checkout.sucursales.isEmpty)
                          Text(
                            'No hay sucursales disponibles en este momento.',
                            style: TextStyle(color: Colors.red.shade700),
                          )
                        else
                          DropdownButtonFormField<int>(
                            isExpanded: true,
                            initialValue: checkout.sucursalId,
                            decoration: InputDecoration(
                              labelText: 'Seleccioná la sucursal',
                              prefixIcon: const Icon(Icons.store_mall_directory_outlined),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            ),
                            items: checkout.sucursales.map((suc) {
                              return DropdownMenuItem<int>(
                                value: suc.id,
                                child: Text(
                                  '${suc.nombre}${suc.ciudad != null && suc.ciudad!.isNotEmpty ? ' (${suc.ciudad})' : ''}',
                                  style: const TextStyle(fontSize: 14),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }).toList(),
                            onChanged: checkout.ventaId != null
                                ? null // No cambiar sucursal si ya se creó la orden (debe pulsar cambiar orden)
                                : (id) => checkout.setSucursalId(id),
                          ),
                        if (checkout.ventaId != null) ...[
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton.icon(
                                onPressed: () => checkout.setSucursalId(checkout.sucursalId),
                                icon: const Icon(Icons.edit_outlined, size: 16),
                                label: const Text('Modificar sucursal', style: TextStyle(fontSize: 12)),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // PASO 2: RESUMEN DE ARTÍCULOS
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Theme.of(context).colorScheme.outline),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 14,
                              backgroundColor: theme.colorScheme.primary,
                              child: const Text('2', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                            ),
                            const SizedBox(width: 10),
                            const Text(
                              'Resumen de compra',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ...carrito.items.map((item) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4.0),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.nombreProducto,
                                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                      ),
                                      Text(
                                        'Talla: ${item.nombreTalla ?? "-"} • Color: ${item.nombreColor ?? "-"} (x${item.cantidad})',
                                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  '\$${item.subtotal.toStringAsFixed(2)}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                              ],
                            ),
                          );
                        }),
                        const Divider(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Total a pagar:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            Text(
                              '\$${(checkout.ventaId != null ? checkout.montoVenta : carrito.total).toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // PASO 3: MÉTODO DE PAGO
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Theme.of(context).colorScheme.outline),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 14,
                              backgroundColor: theme.colorScheme.primary,
                              child: const Text('3', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                            ),
                            const SizedBox(width: 10),
                            const Text(
                              'Método de pago',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            // Tarjeta
                            Expanded(
                              child: InkWell(
                                onTap: () => checkout.setMetodoPago('tarjeta'),
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                                  decoration: BoxDecoration(
                                    color: checkout.metodoPago == 'tarjeta'
                                        ? theme.colorScheme.primary.withValues(alpha: 0.08)
                                        : Colors.white.withValues(alpha: 0.06),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: checkout.metodoPago == 'tarjeta'
                                          ? theme.colorScheme.primary
                                          : Colors.white24,
                                      width: checkout.metodoPago == 'tarjeta' ? 2 : 1,
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      Icon(
                                        Icons.credit_card,
                                        color: checkout.metodoPago == 'tarjeta'
                                            ? theme.colorScheme.primary
                                            : Theme.of(context).colorScheme.onSurfaceVariant,
                                        size: 26,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Tarjeta (Stripe)',
                                        style: TextStyle(
                                          fontWeight: checkout.metodoPago == 'tarjeta' ? FontWeight.bold : FontWeight.normal,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            // QR
                            Expanded(
                              child: InkWell(
                                onTap: () => checkout.setMetodoPago('qr'),
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                                  decoration: BoxDecoration(
                                    color: checkout.metodoPago == 'qr'
                                        ? Colors.purple.withValues(alpha: 0.2)
                                        : Colors.white.withValues(alpha: 0.06),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: checkout.metodoPago == 'qr'
                                          ? Colors.purple.shade700
                                          : Colors.white24,
                                      width: checkout.metodoPago == 'qr' ? 2 : 1,
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      Icon(
                                        Icons.qr_code_scanner,
                                        color: checkout.metodoPago == 'qr'
                                            ? Colors.purple.shade700
                                            : Theme.of(context).colorScheme.onSurfaceVariant,
                                        size: 26,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Código QR',
                                        style: TextStyle(
                                          fontWeight: checkout.metodoPago == 'qr' ? FontWeight.bold : FontWeight.normal,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // PASO 4: FORMULARIO SEGÚN ESTADO Y MÉTODO
                if (checkout.errorMessage != null && checkout.estado == EstadoCheckout.error) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, color: Colors.red.shade700),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            checkout.errorMessage!,
                            style: TextStyle(color: Colors.red.shade900, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Si aún no se creó la orden online
                if (checkout.ventaId == null) ...[
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: checkout.estado == EstadoCheckout.creando || checkout.sucursalId == null
                          ? null
                          : () async {
                              await checkout.crearOrden(
                                sucursalId: checkout.sucursalId!,
                                items: carrito.items,
                              );
                            },
                      icon: checkout.estado == EstadoCheckout.creando
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Icon(Icons.arrow_forward),
                      label: Text(
                        checkout.estado == EstadoCheckout.creando
                            ? 'Creando orden online...'
                            : 'Continuar al pago (\$${(checkout.ventaId != null ? checkout.montoVenta : carrito.total).toStringAsFixed(2)})',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
                  ),
                ] else ...[
                  // Orden ya creada: mostrar pasarela según método
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Theme.of(context).colorScheme.outline),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 14,
                                backgroundColor: theme.colorScheme.primary,
                                child: const Text('4', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                checkout.metodoPago == 'tarjeta'
                                    ? 'Pasarela de Pago con Tarjeta'
                                    : 'Pago y Comprobante QR',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          if (checkout.metodoPago == 'tarjeta')
                            TarjetaForm(
                              ventaId: checkout.ventaId,
                              monto: checkout.montoVenta,
                              onPagoExitoso: () => _onFinalizado(context, esQR: false),
                            )
                          else
                            QrPaymentWidget(
                              ventaId: checkout.ventaId!,
                              monto: checkout.montoVenta,
                              sucursalId: checkout.sucursalId!,
                              onPagoEnviado: () => _onFinalizado(context, esQR: true),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
