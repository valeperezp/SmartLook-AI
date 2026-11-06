import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/config/offline_config.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/puntos_provider.dart';
import '../providers/suscripciones_provider.dart';
import '../widgets/banner_offline.dart';

String _fecha(DateTime f) =>
    '${f.day.toString().padLeft(2, '0')}/${f.month.toString().padLeft(2, '0')} '
    '${f.hour.toString().padLeft(2, '0')}:${f.minute.toString().padLeft(2, '0')}';

/// Perfil del cliente (offline): saldo de puntos de fidelización (CU17) y avisos de stock "Avísame cuando llegue" (CU16).
class PantallaMiCuenta extends StatefulWidget {
  const PantallaMiCuenta({super.key});

  @override
  State<PantallaMiCuenta> createState() => _PantallaMiCuentaState();
}

class _PantallaMiCuentaState extends State<PantallaMiCuenta> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _cargar());
  }

  Future<void> _cargar() async {
    final clienteId = context.read<AuthProvider>().usuario?.id;
    if (!mounted || clienteId == null) return;
    await Future.wait([
      context.read<PuntosProvider>().cargar(clienteId),
      context.read<SuscripcionesProvider>().cargar(clienteId),
    ]);
    if (!mounted) return;
    // Si llegó stock de algo que esperaba, se lo decimos aquí también
    final mensajes = await context.read<SuscripcionesProvider>().revisarAvisos(clienteId);
    if (mensajes.isEmpty || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(mensajes.join('\n')), backgroundColor: Colors.green.shade800, duration: const Duration(seconds: 6)));
  }

  @override
  Widget build(BuildContext context) {
    final usuario = context.watch<AuthProvider>().usuario;
    final puntos = context.watch<PuntosProvider>();
    final suscripciones = context.watch<SuscripcionesProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Mi cuenta')),
      body: Column(
        children: [
          const BannerOffline(),
          Expanded(
            child: usuario == null
                ? const Center(child: Text('Inicia sesión para ver tu cuenta.'))
                : RefreshIndicator(
                    onRefresh: _cargar,
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Text(usuario.nombre, style: Theme.of(context).textTheme.titleLarge),
                        Text('Cliente N.º ${usuario.id}', style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 16),
                        _tarjetaPuntos(puntos),
                        const SizedBox(height: 24),
                        Text('Productos que esperas', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        if (suscripciones.pendientes.isEmpty)
                          const Text('No tienes avisos activos. En el catálogo, toca "Avísame cuando llegue" en una prenda agotada.')
                        else
                          for (final s in suscripciones.pendientes)
                            Card(
                              child: ListTile(
                                leading: const Icon(Icons.notifications_active),
                                title: Text(s.descripcion),
                                subtitle: Text('Desde ${_fecha(s.fecha)}'),
                                trailing: IconButton(
                                  icon: const Icon(Icons.close),
                                  tooltip: 'Cancelar aviso',
                                  onPressed: () => suscripciones.cancelar(s.id, usuario.id),
                                ),
                              ),
                            ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaPuntos(PuntosProvider puntos) {
    final porPunto = OfflineConfig.centavosPorPunto / 100;
    final esquema = Theme.of(context).colorScheme;
    return Card(
      color: esquema.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: esquema.primary.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.stars, color: esquema.primary),
                const SizedBox(width: 8),
                Text('Mis puntos', style: TextStyle(fontWeight: FontWeight.bold, color: esquema.onSurface)),
              ],
            ),
            Text('${puntos.saldo}', style: TextStyle(fontSize: 44, fontWeight: FontWeight.bold, color: esquema.primary)),
            Text('Ganas 1 punto por cada \$${porPunto.toStringAsFixed(0)} de compra.', style: Theme.of(context).textTheme.bodySmall),
            if (puntos.error != null) Text(puntos.error!, style: const TextStyle(color: Colors.red)),
            if (puntos.movimientos.isNotEmpty) ...[
              const Divider(height: 24),
              for (final m in puntos.movimientos.take(10))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(m.delta >= 0 ? Icons.add_circle : Icons.remove_circle, color: m.delta >= 0 ? Colors.green : Colors.red),
                  title: Text('${m.delta > 0 ? '+' : ''}${m.delta} punto(s) · ${m.tipo == 'ganado' ? 'compra' : (m.tipo == 'perdido' ? 'devolución' : 'canje')}'),
                  subtitle: Text(_fecha(m.fecha)),
                  trailing: Icon(m.sincronizado ? Icons.cloud_done : Icons.cloud_upload_outlined, size: 18, color: m.sincronizado ? Colors.green : Colors.orange),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
