import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../../core/config/env.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/loading_state.dart';
import '../../../auth/providers/auth_provider.dart';
import '../providers/qr_cajero_provider.dart';
import '../widgets/qr_mostrar_widget.dart';

class QrCajeroScreen extends StatefulWidget {
  final int? ventaId;
  final double? monto;

  const QrCajeroScreen({
    super.key,
    this.ventaId,
    this.monto,
  });

  @override
  State<QrCajeroScreen> createState() => _QrCajeroScreenState();
}

class _QrCajeroScreenState extends State<QrCajeroScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _iniciar();
    });
  }

  void _iniciar() {
    final auth = context.read<AuthProvider>();
    final sucursalId = auth.usuario?.sucursalId ?? 1;
    final vId = widget.ventaId;

    if (vId != null && vId > 0) {
      context.read<QrCajeroProvider>().iniciarCobroQR(
            ventaId: vId,
            sucursalId: sucursalId,
          );
    }
  }

  String _resolverUrl(String? url) {
    if (url == null || url.isEmpty) return '';
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    if (url.startsWith('/')) return '${Env.apiUrl}$url';
    return '${Env.apiUrl}/$url';
  }

  void _confirmarAprobacion(BuildContext context, int pagoId) async {
    final messenger = ScaffoldMessenger.of(context);
    final prov = context.read<QrCajeroProvider>();

    final ok = await prov.aprobarPago(pagoId);
    if (!mounted) return;

    if (ok) {
      messenger.showSnackBar(
        SnackBar(
          content: const Text('¡Pago QR aprobado y verificado con éxito!'),
          backgroundColor: Colors.green.shade700,
        ),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(prov.errorMessage ?? 'Error al confirmar el pago'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  void _confirmarRechazo(BuildContext context, int pagoId) {
    final motivoCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.cancel_outlined, color: Colors.red.shade600),
              const SizedBox(width: 8),
              const Text('Rechazar Pago'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Indica el motivo del rechazo del comprobante:'),
              const SizedBox(height: 12),
              TextField(
                controller: motivoCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: 'Ej: Comprobante ilegible o monto incorrecto...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                final motivo = motivoCtrl.text.trim();
                final prov = context.read<QrCajeroProvider>();
                Navigator.of(ctx).pop();

                final ok = await prov.rechazarPago(
                  pagoId,
                  motivo.isNotEmpty ? motivo : 'Comprobante rechazado por el cajero',
                );
                if (!mounted) return;

                if (ok) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: const Text('Pago rechazado.'),
                      backgroundColor: Colors.orange.shade800,
                    ),
                  );
                } else {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(prov.errorMessage ?? 'Error al rechazar el pago'),
                      backgroundColor: Colors.red.shade700,
                    ),
                  );
                }
              },
              child: const Text('Rechazar'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<QrCajeroProvider>();
    final pago = provider.pago;
    final vId = widget.ventaId ?? pago?.ventaId ?? 0;
    final montoTotal = widget.monto ?? pago?.monto ?? 0.0;

    if (vId == 0) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Cobro QR', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          backgroundColor: Colors.blue.shade800,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => context.go('/cajero/pos'),
          ),
        ),
        body: EmptyState(
          icono: Icons.qr_code,
          titulo: 'Sin venta activa',
          mensaje: 'No hay ninguna venta seleccionada para cobro QR. Creá una venta desde el POS.',
          onReintentar: () => context.go('/cajero/pos'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Cobro QR en Caja',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.blue.shade800,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            provider.detenerPolling();
            context.go('/cajero/pos');
          },
        ),
      ),
      body: provider.isLoading && pago == null
          ? const LoadingState(mensaje: 'Generando orden de pago QR...')
          : provider.errorMessage != null && pago == null
              ? EmptyState(
                  icono: Icons.error_outline,
                  titulo: 'Error al iniciar cobro QR',
                  mensaje: provider.errorMessage,
                  onReintentar: _iniciar,
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 650),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Estado 3: ¡Pago Aprobado con Éxito!
                          if (provider.pagoCompletado) ...[
                            Card(
                              elevation: 3,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              child: Padding(
                                padding: const EdgeInsets.all(32),
                                child: Column(
                                  children: [
                                    Icon(Icons.check_circle, size: 72, color: Colors.green.shade600),
                                    const SizedBox(height: 16),
                                    const Text(
                                      '¡Cobro QR Completado!',
                                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Venta #$vId pagada exitosamente por \$${montoTotal.toStringAsFixed(2)}',
                                      style: TextStyle(color: Colors.grey.shade700, fontSize: 15),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 28),
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.blue.shade700,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(vertical: 14),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                        ),
                                        icon: const Icon(Icons.point_of_sale),
                                        label: const Text(
                                          'Nueva Venta / Volver al POS',
                                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                        ),
                                        onPressed: () {
                                          provider.reset();
                                          context.go('/cajero/pos');
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ] else ...[
                            // Tarjeta con Monto y Ticket
                            Card(
                              elevation: 1.5,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Ticket #$vId',
                                            style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                                        const SizedBox(height: 2),
                                        const Text('Monto a Cobrar',
                                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                      ],
                                    ),
                                    Text(
                                      '\$${montoTotal.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.deepOrange,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),

                            // Widget del Código QR
                            if (pago != null)
                              QrMostrarWidget(
                                urlComprobante: '${Env.webUrl}/pago/${pago.id}/comprobante',
                                qrSucursal: provider.qrSucursal,
                              ),
                            const SizedBox(height: 20),

                            // Estado del Comprobante (Polling o Recibido)
                            if (provider.esperandoComprobante) ...[
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: Colors.blue.shade200),
                                ),
                                child: Row(
                                  children: [
                                    const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Text(
                                        'Esperando que el cliente transfiera y adjunte su comprobante...',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.blue.shade900,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ] else if (provider.comprobanteRecibido && pago != null) ...[
                              // Comprobante Recibido: Mostrar Preview
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade50,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: Colors.green.shade300),
                                ),
                                child: Column(
                                  children: [
                                    Row(
                                      children: [
                                        Icon(Icons.check_circle, color: Colors.green.shade700, size: 22),
                                        const SizedBox(width: 10),
                                        const Expanded(
                                          child: Text(
                                            '¡Comprobante de pago recibido!',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.black87,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),

                                    // Preview de la imagen
                                    if (pago.comprobanteUrl != null || pago.comprobantePath != null)
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(10),
                                        child: Image.network(
                                          _resolverUrl(pago.comprobanteUrl ?? pago.comprobantePath),
                                          height: 180,
                                          fit: BoxFit.contain,
                                          errorBuilder: (context, error, stackTrace) => Container(
                                            height: 100,
                                            color: Colors.grey.shade200,
                                            child: const Center(
                                              child: Text('Error al cargar imagen del comprobante'),
                                            ),
                                          ),
                                        ),
                                      ),
                                    const SizedBox(height: 16),

                                    // Botones Aprobar / Rechazar
                                    Row(
                                      children: [
                                        Expanded(
                                          child: OutlinedButton(
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: Colors.red.shade700,
                                              side: BorderSide(color: Colors.red.shade300),
                                              padding: const EdgeInsets.symmetric(vertical: 12),
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                            ),
                                            onPressed: provider.isProcesando
                                                ? null
                                                : () => _confirmarRechazo(context, pago.id),
                                            child: const Text('Rechazar'),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: ElevatedButton(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.green.shade600,
                                              foregroundColor: Colors.white,
                                              padding: const EdgeInsets.symmetric(vertical: 12),
                                              elevation: 0,
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                            ),
                                            onPressed: provider.isProcesando
                                                ? null
                                                : () => _confirmarAprobacion(context, pago.id),
                                            child: Text(
                                              provider.isProcesando ? 'Verificando...' : 'Aprobar Pago',
                                              style: const TextStyle(fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 24),

                            // Botón cancelar
                            TextButton.icon(
                              style: TextButton.styleFrom(foregroundColor: Colors.grey.shade700),
                              icon: const Icon(Icons.close),
                              label: const Text('Cancelar cobro QR y volver al POS'),
                              onPressed: () {
                                provider.detenerPolling();
                                context.go('/cajero/pos');
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
    );
  }
}
