import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/config/env.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/loading_state.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../../checkout/models/pago.dart';
import '../providers/pagos_pendientes_provider.dart';
import '../widgets/pago_pendiente_card.dart';

class PagosPendientesScreen extends StatefulWidget {
  const PagosPendientesScreen({super.key});

  @override
  State<PagosPendientesScreen> createState() => _PagosPendientesScreenState();
}

class _PagosPendientesScreenState extends State<PagosPendientesScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _recargar(silencioso: false);
    });

    // Auto-refresco cada 15 segundos para capturar nuevos pagos o comprobantes
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) {
        _recargar(silencioso: true);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _recargar({bool silencioso = false}) {
    final auth = context.read<AuthProvider>();
    final sucursalId = auth.usuario?.sucursalId;
    context.read<PagosPendientesProvider>().cargarPendientes(sucursalId, silencioso: silencioso);
  }

  String _resolverUrl(String? url) {
    if (url == null || url.isEmpty) return '';
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    if (url.startsWith('/')) return '${Env.apiUrl}$url';
    return '${Env.apiUrl}/$url';
  }

  void _verComprobante(BuildContext context, Pago pago) {
    final url = _resolverUrl(pago.comprobanteUrl ?? pago.comprobantePath);
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Este pago no tiene comprobante cargado')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.topRight,
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.75,
                    maxWidth: MediaQuery.of(context).size.width * 0.9,
                  ),
                  color: Colors.black,
                  child: InteractiveViewer(
                    panEnabled: true,
                    minScale: 0.5,
                    maxScale: 4.0,
                    child: Image.network(
                      url,
                      fit: BoxFit.contain,
                      loadingBuilder: (_, child, progress) {
                        if (progress == null) return child;
                        return const Padding(
                          padding: EdgeInsets.all(40),
                          child: Center(
                            child: CircularProgressIndicator(color: Colors.white),
                          ),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) => const Padding(
                        padding: EdgeInsets.all(30),
                        child: Center(
                          child: Text(
                            'No se pudo cargar la imagen del comprobante',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Comprobante Pago #${pago.id} — Venta #${pago.ventaId}',
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _confirmarAprobacion(BuildContext context, Pago pago) {
    final montoTxt = pago.montoFormateado.isNotEmpty
        ? pago.montoFormateado
        : '\$${pago.monto.toStringAsFixed(2)}';

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.check_circle_outline, color: Colors.green.shade600),
              const SizedBox(width: 8),
              const Text('Aprobar Pago'),
            ],
          ),
          content: Text(
            '¿Confirmas la recepción del pago # ${pago.id} de $montoTxt para la Venta #${pago.ventaId}?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade600,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                final prov = context.read<PagosPendientesProvider>();
                Navigator.of(ctx).pop();
                final ok = await prov.confirmarPago(pago.id);
                if (!mounted) return;
                if (ok) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('Pago #${pago.id} aprobado exitosamente.'),
                      backgroundColor: Colors.green.shade700,
                    ),
                  );
                } else {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(prov.errorMessage ?? 'Error al aprobar el pago.'),
                      backgroundColor: Colors.red.shade700,
                    ),
                  );
                }
              },
              child: const Text('Confirmar'),
            ),
          ],
        );
      },
    );
  }

  void _confirmarRechazo(BuildContext context, Pago pago) {
    final motivoController = TextEditingController();

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
              Text(
                'Indica el motivo del rechazo del comprobante para el Pago #${pago.id}:',
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: motivoController,
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: 'Ej: Comprobante ilegible o monto incorrecto...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
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
                final motivo = motivoController.text.trim();
                final prov = context.read<PagosPendientesProvider>();
                Navigator.of(ctx).pop();
                final ok = await prov.rechazarPago(
                  pago.id,
                  motivo.isNotEmpty ? motivo : 'Comprobante no válido',
                );
                if (!mounted) return;
                if (ok) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('Pago #${pago.id} rechazado.'),
                      backgroundColor: Colors.orange.shade800,
                    ),
                  );
                } else {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(prov.errorMessage ?? 'Error al rechazar el pago.'),
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
    final provider = context.watch<PagosPendientesProvider>();
    final pagos = provider.pagos;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text(
              'Pagos QR Pendientes',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
            ),
            if (provider.totalPendientes > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${provider.totalPendientes}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange.shade800,
                  ),
                ),
              ),
            ],
          ],
        ),
        backgroundColor: Colors.orange.shade800,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
            onPressed: () => _recargar(silencioso: false),
          ),
        ],
      ),
      body: provider.isLoading && pagos.isEmpty
          ? const LoadingState(mensaje: 'Consultando pagos pendientes...')
          : provider.errorMessage != null && pagos.isEmpty
              ? EmptyState(
                  icono: Icons.error_outline,
                  titulo: 'Error al consultar pagos',
                  mensaje: provider.errorMessage,
                  onReintentar: () => _recargar(silencioso: false),
                )
              : RefreshIndicator(
                  onRefresh: () async => _recargar(silencioso: false),
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 800),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header resumen KPIs
                            Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.shade50,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.amber.shade200),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(Icons.pending_actions,
                                            size: 32, color: Colors.amber.shade800),
                                        const SizedBox(width: 12),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Pagos por revisar',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.amber.shade900,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              '${provider.totalPendientes}',
                                              style: TextStyle(
                                                fontSize: 20,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.amber.shade900,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: Colors.green.shade50,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.green.shade200),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(Icons.attach_money,
                                            size: 32, color: Colors.green.shade700),
                                        const SizedBox(width: 12),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Monto pendiente',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.green.shade900,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              '\$${provider.montoTotal.toStringAsFixed(2)}',
                                              style: TextStyle(
                                                fontSize: 20,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.green.shade900,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),

                            // Listado de tarjetas de pagos
                            if (pagos.isEmpty)
                              EmptyState(
                                icono: Icons.check_circle_outline,
                                titulo: 'Al día',
                                mensaje: 'No hay pagos QR pendientes de verificación para esta sucursal.',
                                onReintentar: () => _recargar(silencioso: false),
                              )
                            else
                              ListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: pagos.length,
                                itemBuilder: (context, index) {
                                  final pago = pagos[index];
                                  return PagoPendienteCard(
                                    pago: pago,
                                    isProcessing: provider.isProcessing,
                                    onAprobar: () => _confirmarAprobacion(context, pago),
                                    onRechazar: () => _confirmarRechazo(context, pago),
                                    onVerComprobante: () => _verComprobante(context, pago),
                                  );
                                },
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
