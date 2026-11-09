import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/models/venta.dart';
import '../../../core/utils/app_notifications.dart';
import '../../../core/widgets/loading_state.dart';
import '../../offline/services/sync_service.dart';
import '../../reservas/providers/reservas_provider.dart' show ResultadoQr;
import '../../reservas/widgets/banner_reembolso.dart';
import '../../reservas/widgets/selector_qr.dart';
import '../providers/ventas_provider.dart';
import '../widgets/venta_tile.dart';

class MisComprasScreen extends StatefulWidget {
  const MisComprasScreen({super.key, this.selectorQr, this.sincronizar});

  /// Cómo se elige el QR del reembolso (por defecto: cámara o galería con image_picker). Las pruebas lo reemplazan.
  final SelectorQr? selectorQr;

  /// Cómo se envía lo pendiente al adjuntar el QR (por defecto: el `SyncService` de la app).
  final Future<ResultadoSync> Function()? sincronizar;

  @override
  State<MisComprasScreen> createState() => _MisComprasScreenState();
}

class _MisComprasScreenState extends State<MisComprasScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<VentasProvider>().cargarCompras();
    });
  }

  /// El cliente toca el banner rojo de una compra rechazada: elige su QR bancario (cámara o galería) y se guarda en la cola de
  /// sincronización. Si hay red se envía enseguida; si no, queda guardado y se envía solo cuando vuelva la conexión.
  Future<void> _adjuntarQr(Venta venta) async {
    final elegido = await (widget.selectorQr ?? elegirQrConImagePicker)(context);
    if (elegido == null || !mounted) return;

    final provider = context.read<VentasProvider>();
    final sincronizar = widget.sincronizar ?? context.read<SyncService>().sincronizarPendientes;
    final r = await provider.adjuntarQr(venta, imagen: elegido.bytes, nombreArchivo: elegido.nombre, sincronizar: sincronizar);
    if (!mounted) return;

    switch (r.resultado) {
      case ResultadoQr.enviado:
        AppNotifications.success(context, r.mensaje);
      case ResultadoQr.enCola:
        AppNotifications.info(context, r.mensaje);
      case ResultadoQr.rechazado:
      case ResultadoQr.invalido:
        AppNotifications.error(context, r.mensaje);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Mis Compras',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.blue.shade700,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'Actualizar',
            onPressed: () => context.read<VentasProvider>().cargarCompras(),
          ),
        ],
      ),
      body: Consumer<VentasProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading && provider.compras.isEmpty) {
            return const LoadingState(mensaje: 'Cargando tus compras online...');
          }

          if (provider.errorMessage != null && provider.compras.isEmpty) {
            return EmptyState(
              icono: Icons.error_outline,
              titulo: 'Error al consultar tus compras',
              mensaje: provider.errorMessage!,
              textoBoton: 'Reintentar',
              onReintentar: () => provider.cargarCompras(),
            );
          }

          if (provider.compras.isEmpty) {
            return EmptyState(
              icono: Icons.shopping_bag_outlined,
              titulo: 'Aún no tenés compras online',
              mensaje:
                  'Explorá nuestras colecciones de prendas y realizá tu primer pedido desde la tienda.',
              textoBoton: 'Ir al Catálogo',
              onReintentar: () => context.go('/'),
            );
          }

          return RefreshIndicator(
            onRefresh: () => provider.cargarCompras(),
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 10),
              itemCount: provider.compras.length,
              itemBuilder: (context, index) {
                final venta = provider.compras[index];
                return Column(
                  children: [
                    VentaTile(venta: venta),
                    // Compra rechazada con reembolso pendiente → pide el QR bancario (funciona sin conexión)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: BannerReembolsoPedido(
                        tipo: tipoBannerReembolsoDe(
                          admiteReembolso: venta.admiteReembolso,
                          tieneQr: venta.reembolso?.tieneQr == true,
                          local: provider.qrLocalDe(venta),
                        ),
                        local: provider.qrLocalDe(venta),
                        textoAdjuntar: BannerReembolsoPedido.textoAdjuntarCompra,
                        onAdjuntar: () => _adjuntarQr(venta),
                      ),
                    ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }
}
