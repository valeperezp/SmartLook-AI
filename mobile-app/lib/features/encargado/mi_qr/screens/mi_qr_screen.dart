import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../../core/config/env.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/loading_state.dart';
import '../../../auth/providers/auth_provider.dart';
import '../providers/sucursal_qr_provider.dart';
import '../widgets/qr_upload_widget.dart';

class MiQrScreen extends StatefulWidget {
  const MiQrScreen({super.key});

  @override
  State<MiQrScreen> createState() => _MiQrScreenState();
}

class _MiQrScreenState extends State<MiQrScreen> {
  bool _mostrarReemplazo = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _recargar();
    });
  }

  void _recargar() {
    final auth = context.read<AuthProvider>();
    final sucursalId = auth.usuario?.sucursalId;
    if (sucursalId != null) {
      context.read<SucursalQrProvider>().cargarQR(sucursalId);
    }
  }

  String _resolverUrl(String? url) {
    if (url == null || url.isEmpty) return '';
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    if (url.startsWith('/')) return '${Env.apiUrl}$url';
    return '${Env.apiUrl}/$url';
  }

  void _confirmarDesactivar(BuildContext context, int sucursalId) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red),
              SizedBox(width: 8),
              Text('Desactivar QR'),
            ],
          ),
          content: const Text(
            '¿Estás seguro de que deseas desactivar el código QR de cobro de esta sucursal? Los clientes ya no podrán pagar con este código hasta que se configure uno nuevo.',
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
                final prov = context.read<SucursalQrProvider>();
                Navigator.of(ctx).pop();
                final ok = await prov.desactivarQR(sucursalId);
                if (!mounted) return;
                if (ok) {
                  setState(() {
                    _mostrarReemplazo = false;
                  });
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('Código QR desactivado exitosamente.'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                } else {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(prov.errorMessage ?? 'Error al desactivar el QR'),
                      backgroundColor: Colors.red.shade700,
                    ),
                  );
                }
              },
              child: const Text('Desactivar'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final sucursalId = auth.usuario?.sucursalId;
    final sucursalNombre = auth.usuario?.sucursalNombre ?? 'Sucursal';
    final provider = context.watch<SucursalQrProvider>();
    final qr = provider.qr;

    if (sucursalId == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Mi QR Sucursal'),
          backgroundColor: Colors.orange.shade800,
        ),
        body: const Center(
          child: Text('No tienes una sucursal asignada.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Mi QR de Sucursal',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.orange.shade800,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
            onPressed: _recargar,
          ),
        ],
      ),
      body: provider.isLoading && qr == null
          ? const LoadingState(mensaje: 'Consultando código QR de la sucursal...')
          : provider.errorMessage != null && qr == null
              ? EmptyState(
                  icono: Icons.error_outline,
                  titulo: 'Error al cargar QR',
                  mensaje: provider.errorMessage,
                  onReintentar: _recargar,
                )
              : RefreshIndicator(
                  onRefresh: () async => _recargar(),
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(20),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 700),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Chip de sucursal
                            Chip(
                              avatar: const Icon(Icons.store, size: 16, color: Colors.deepOrange),
                              label: Text(
                                'Sucursal: $sucursalNombre',
                                style: TextStyle(
                                  color: Colors.orange.shade900,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              backgroundColor: Colors.orange.shade50,
                            ),
                            const SizedBox(height: 20),

                            // Caso 1: Tiene QR activo y NO está en modo reemplazo
                            if (qr != null && qr.activo && !_mostrarReemplazo) ...[
                              Card(
                                elevation: 3,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Column(
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: Colors.green.shade50,
                                              borderRadius: BorderRadius.circular(20),
                                              border: Border.all(
                                                  color: Colors.green.shade300),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.check_circle,
                                                    size: 14,
                                                    color: Colors.green.shade700),
                                                const SizedBox(width: 6),
                                                Text(
                                                  'QR ACTIVO PARA COBRO',
                                                  style: TextStyle(
                                                    color: Colors.green.shade800,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 20),

                                      // Imagen del QR
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(16),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withValues(alpha: 0.06),
                                              blurRadius: 10,
                                              offset: const Offset(0, 4),
                                            ),
                                          ],
                                        ),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(12),
                                          child: Image.network(
                                            _resolverUrl(qr.imagenUrl),
                                            width: 250,
                                            height: 250,
                                            fit: BoxFit.contain,
                                            loadingBuilder: (_, child, progress) {
                                              if (progress == null) return child;
                                              return const SizedBox(
                                                width: 250,
                                                height: 250,
                                                child: Center(
                                                  child: CircularProgressIndicator(),
                                                ),
                                              );
                                            },
                                            errorBuilder: (context, error, stackTrace) =>
                                                const SizedBox(
                                              width: 250,
                                              height: 250,
                                              child: Center(
                                                child: Column(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(Icons.broken_image,
                                                        size: 48,
                                                        color: Colors.grey),
                                                    SizedBox(height: 8),
                                                    Text(
                                                      'Error al cargar imagen QR',
                                                      style: TextStyle(
                                                          color: Colors.grey),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        'Configurado el ${DateFormat("dd/MM/yyyy HH:mm").format(qr.creadoEn.toLocal())}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                      const SizedBox(height: 24),

                                      // Botones de acción: Desactivar o Reemplazar
                                      Row(
                                        children: [
                                          Expanded(
                                            child: OutlinedButton.icon(
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor: Colors.red.shade700,
                                                side: BorderSide(
                                                    color: Colors.red.shade300),
                                                padding: const EdgeInsets.symmetric(
                                                    vertical: 14),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                              ),
                                              icon: const Icon(Icons.delete_outline),
                                              label: const Text('Desactivar QR'),
                                              onPressed: () =>
                                                  _confirmarDesactivar(
                                                      context, sucursalId),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: ElevatedButton.icon(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor:
                                                    Colors.orange.shade800,
                                                foregroundColor: Colors.white,
                                                padding: const EdgeInsets.symmetric(
                                                    vertical: 14),
                                                elevation: 0,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                              ),
                                              icon: const Icon(Icons.swap_horiz),
                                              label: const Text('Reemplazar QR'),
                                              onPressed: () {
                                                setState(() {
                                                  _mostrarReemplazo = true;
                                                });
                                              },
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ] else ...[
                              // Caso 2: No tiene QR o está reemplazando
                              if (_mostrarReemplazo) ...[
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'Reemplazar código QR',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        setState(() {
                                          _mostrarReemplazo = false;
                                        });
                                      },
                                      child: const Text('Cancelar reemplazo'),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                              ],
                              QrUploadWidget(
                                isSubiendo: provider.isSubiendo,
                                onSubir: (archivo) async {
                                  final messenger = ScaffoldMessenger.of(context);
                                  final ok = await provider.subirQR(
                                      sucursalId, archivo);
                                  if (!mounted) return;
                                  if (ok) {
                                    setState(() {
                                      _mostrarReemplazo = false;
                                    });
                                    messenger.showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                            'Código QR subido y activado exitosamente.'),
                                        backgroundColor: Colors.green,
                                      ),
                                    );
                                  } else {
                                    messenger.showSnackBar(
                                      SnackBar(
                                        content: Text(provider.errorMessage ??
                                            'Error al subir el QR'),
                                        backgroundColor: Colors.red.shade700,
                                      ),
                                    );
                                  }
                                },
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
    );
  }
}
