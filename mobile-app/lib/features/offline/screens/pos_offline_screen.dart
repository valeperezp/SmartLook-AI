import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/config/offline_config.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/catalogo_item.dart';
import '../providers/turno_caja_provider.dart';
import '../providers/venta_offline_provider.dart';
import '../services/sync_service.dart';
import '../widgets/banner_offline.dart';

String _dinero(int centavos) => '\$${(centavos / 100).toStringAsFixed(2)}';

/// Punto de venta del cajero que funciona sin red: catálogo y venta viven en SQLite.
class PosOfflineScreen extends StatefulWidget {
  const PosOfflineScreen({super.key});

  @override
  State<PosOfflineScreen> createState() => _PosOfflineScreenState();
}

class _PosOfflineScreenState extends State<PosOfflineScreen> {
  bool _sincronizando = false;
  StreamSubscription<ResultadoSync>? _autoSync;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final sucursalId = context.read<AuthProvider>().usuario?.sucursalId;
      if (sucursalId != null) context.read<VentaOfflineProvider>().cargar(sucursalId);
      // Sincronización automática (al volver la red): refresca el stock, que pudo cambiar por rechazos
      _autoSync = context.read<SyncService>().alSincronizarAutomaticamente.listen((r) {
        if (!mounted) return;
        final id = context.read<AuthProvider>().usuario?.sucursalId;
        if (id != null) context.read<VentaOfflineProvider>().cargar(id);
        _avisar('Sincronización automática: ${r.resumen}');
      });
    });
  }

  @override
  void dispose() {
    _autoSync?.cancel();
    super.dispose();
  }

  void _avisar(String? mensaje) {
    if (mensaje == null || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(mensaje), duration: const Duration(seconds: 2)));
  }

  Future<void> _cobrar() async {
    final provider = context.read<VentaOfflineProvider>();
    final usuario = context.read<AuthProvider>().usuario;
    final sucursalId = usuario?.sucursalId;
    if (usuario == null || sucursalId == null) return;

    // Sin caja abierta no se cobra: se manda al cajero a abrirla
    final turnos = context.read<TurnoCajaProvider>();
    await turnos.cargar(usuario.id, sucursalId);
    if (!mounted) return;
    final turno = turnos.turno;
    if (turno == null) {
      final abrir = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          icon: const Icon(Icons.lock, size: 40),
          title: const Text('Caja cerrada'),
          content: const Text('Para cobrar primero tienes que abrir tu caja con el monto inicial.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Ahora no')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Abrir caja')),
          ],
        ),
      );
      if (abrir == true && mounted) context.push('/offline/turno');
      return;
    }

    final total = provider.calcularTotal();
    final cobro = await showDialog<({int? recibido, int? clienteId})>(
      context: context,
      builder: (_) => _CobroDialog(totalCentavos: total),
    );
    if (cobro == null || !mounted) return; // canceló

    final ok = await provider.procesarVenta(
      cajeroId: usuario.id,
      sucursalId: sucursalId,
      montoRecibidoCentavos: cobro.recibido,
      turnoUuid: turno.id,
      clienteId: cobro.clienteId,
    );
    if (!mounted) return;
    if (ok) {
      await turnos.refrescar(); // el monto esperado del turno cambió
      if (!mounted) return;
    }
    if (!ok) {
      _avisar(provider.ultimoMensaje);
      return;
    }
    final cambio = cobro.recibido == null ? null : cobro.recibido! - total;
    final puntos = provider.puntosUltimaVenta;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        icon: const Icon(Icons.check_circle, color: Colors.green, size: 48),
        title: const Text('Venta guardada'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Venta guardada localmente. Pendiente de sincronizar.', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Text('Total: ${_dinero(total)}', style: const TextStyle(fontWeight: FontWeight.bold)),
            if (cambio != null)
              Text('Cambio: ${_dinero(cambio)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            if (cobro.clienteId != null && puntos > 0) ...[
              const SizedBox(height: 8),
              Text('Cliente ${cobro.clienteId}: +$puntos punto(s)', style: TextStyle(color: Colors.green.shade800, fontWeight: FontWeight.w600)),
            ],
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Aceptar'))],
      ),
    );
  }

  /// TEMPORAL: dispara la sincronización a mano y muestra el resultado.
  Future<void> _sincronizar() async {
    setState(() => _sincronizando = true);
    String mensaje;
    try {
      mensaje = (await context.read<SyncService>().sincronizarPendientes()).resumen;
    } catch (e, st) {
      debugPrint('[PosOfflineScreen] Error al sincronizar: $e\n$st');
      mensaje = 'Error al sincronizar. Las operaciones siguen guardadas en el dispositivo.';
    }
    if (!mounted) return;
    setState(() => _sincronizando = false);
    _avisar(mensaje);
    // un rechazo devuelve stock al catálogo local: se vuelve a leer para mostrarlo
    final sucursalId = context.read<AuthProvider>().usuario?.sucursalId;
    if (sucursalId != null) await context.read<VentaOfflineProvider>().cargar(sucursalId);
  }

  Future<void> _cargarMock(int sucursalId) async {
    final provider = context.read<VentaOfflineProvider>();
    await provider.cargarDatosMock(sucursalId);
    _avisar(provider.ultimoMensaje);
  }

  @override
  Widget build(BuildContext context) {
    final sucursalId = context.watch<AuthProvider>().usuario?.sucursalId;
    final provider = context.watch<VentaOfflineProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('POS offline'),
        actions: [
          IconButton(
            icon: const Icon(Icons.swap_horiz),
            tooltip: 'Cambios/Devoluciones',
            onPressed: () => context.push('/offline/devoluciones'),
          ),
          IconButton(
            icon: const Icon(Icons.account_balance_wallet),
            tooltip: 'Mi Caja',
            onPressed: () => context.push('/offline/turno'),
          ),
          // TEMPORAL: sincronización manual (fase de pruebas)
          TextButton.icon(
            onPressed: _sincronizando || provider.procesando ? null : _sincronizar,
            icon: _sincronizando
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.sync),
            label: const Text('Sincronizar Datos'),
          ),
          if (kDebugMode && provider.soportado && sucursalId != null)
            TextButton.icon(
              onPressed: provider.cargando || provider.procesando ? null : () => _cargarMock(sucursalId),
              icon: const Icon(Icons.dataset),
              label: const Text('Cargar Datos Mock'),
            ),
        ],
      ),
      body: sucursalId == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Tu usuario no tiene una sucursal asignada. Pídele a un administrador que te asigne una.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : Column(
              children: [
                const BannerOffline(),
                Expanded(flex: 5, child: _productos(provider)),
                const Divider(height: 1, thickness: 2),
                Expanded(flex: 4, child: _carrito(provider)),
              ],
            ),
    );
  }

  Widget _productos(VentaOfflineProvider provider) {
    if (provider.cargando && provider.productos.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (provider.error != null) {
      return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(provider.error!)));
    }
    if (provider.productos.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No hay catálogo guardado en el dispositivo para esta sucursal.\nUsa "Cargar Datos Mock" para probar.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 150,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 0.9,
      ),
      itemCount: provider.productos.length,
      itemBuilder: (context, i) {
        final p = provider.productos[i];
        final restante = provider.disponibleParaAgregar(p);
        return _TarjetaPos(
          producto: p,
          restante: restante,
          enCarrito: provider.cantidadEnCarrito(p),
          onTap: restante > 0 && !provider.procesando ? () => _avisarSi(provider.agregarProducto(p), provider) : null,
        );
      },
    );
  }

  void _avisarSi(bool agregado, VentaOfflineProvider provider) {
    if (!agregado) _avisar(provider.ultimoMensaje);
  }

  Widget _carrito(VentaOfflineProvider provider) {
    final total = provider.calcularTotal();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
          child: Row(
            children: [
              Expanded(
                child: Text('Carrito (${provider.unidadesEnCarrito})',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              TextButton.icon(
                onPressed: provider.carritoVacio || provider.procesando ? null : provider.limpiarCarrito,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Vaciar'),
              ),
            ],
          ),
        ),
        Expanded(
          child: provider.carritoVacio
              ? const Center(child: Text('Toca un producto para agregarlo'))
              : ListView.builder(
                  itemCount: provider.lineas.length,
                  itemBuilder: (context, i) {
                    final l = provider.lineas[i];
                    final puedeMas = provider.disponibleParaAgregar(l.producto) > 0;
                    return ListTile(
                      dense: true,
                      title: Text(l.producto.nombre, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('${l.producto.variante.isEmpty ? "" : "${l.producto.variante} · "}'
                          '${l.producto.precioTexto} c/u'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline),
                            tooltip: 'Quitar uno',
                            onPressed: provider.procesando ? null : () => provider.quitarProducto(l.producto),
                          ),
                          Text('${l.cantidad}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline),
                            tooltip: 'Agregar uno',
                            onPressed: puedeMas && !provider.procesando
                                ? () => _avisarSi(provider.agregarProducto(l.producto), provider)
                                : null,
                          ),
                          SizedBox(
                            width: 64,
                            child: Text(_dinero(l.subtotalCentavos),
                                textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          child: Column(
            children: [
              Row(
                children: [
                  const Text('TOTAL', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  Text(_dinero(total), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton.icon(
                  onPressed: provider.carritoVacio || provider.procesando ? null : _cobrar,
                  icon: provider.procesando
                      ? const SizedBox(
                          width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.payments),
                  label: const Text('COBRAR EN EFECTIVO', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TarjetaPos extends StatelessWidget {
  const _TarjetaPos({required this.producto, required this.restante, required this.enCarrito, required this.onTap});

  final CatalogoItem producto;
  final int restante;
  final int enCarrito;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final agotado = restante <= 0;
    return Card(
      clipBehavior: Clip.antiAlias,
      color: agotado ? Colors.grey.shade200 : null,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.checkroom, size: 20, color: agotado ? Colors.grey : Colors.blue.shade700),
                  const Spacer(),
                  if (enCarrito > 0)
                    Badge(label: Text('$enCarrito'), backgroundColor: Colors.blue.shade700),
                ],
              ),
              const SizedBox(height: 4),
              Text(producto.nombre,
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
              if (producto.variante.isNotEmpty)
                Text(producto.variante, style: Theme.of(context).textTheme.bodySmall),
              const Spacer(),
              Text(producto.precioTexto, style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(
                agotado ? 'Agotado' : 'Stock: $restante',
                style: TextStyle(fontSize: 12, color: agotado ? Colors.red.shade700 : Colors.green.shade700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CobroDialog extends StatefulWidget {
  const _CobroDialog({required this.totalCentavos});

  final int totalCentavos;

  @override
  State<_CobroDialog> createState() => _CobroDialogState();
}

class _CobroDialogState extends State<_CobroDialog> {
  final _controller = TextEditingController();
  final _cliente = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    _cliente.dispose();
    super.dispose();
  }

  /// Vacío = venta sin cliente (válido). Un número entero positivo = cliente registrado. Otra cosa = inválido.
  ({bool valido, int? id}) get _lecturaCliente {
    final texto = _cliente.text.trim();
    if (texto.isEmpty) return (valido: true, id: null);
    final id = RegExp(r'^\d{1,9}$').hasMatch(texto) ? int.parse(texto) : null;
    return (valido: id != null && id > 0, id: id);
  }

  /// Vacío = no se ingresó monto (válido). `null` en el record interno = texto inválido.
  ({bool valido, int? recibido}) get _lectura {
    final texto = _controller.text.trim();
    if (texto.isEmpty) return (valido: true, recibido: null);
    final c = VentaOfflineProvider.parseMonto(texto);
    return (valido: c != null && c >= widget.totalCentavos, recibido: c);
  }

  @override
  Widget build(BuildContext context) {
    final lectura = _lectura;
    final texto = _controller.text.trim();
    final cambio = lectura.recibido == null ? null : lectura.recibido! - widget.totalCentavos;
    final cliente = _lecturaCliente;
    final puntos = OfflineConfig.puntosPara(widget.totalCentavos);

    return AlertDialog(
      title: const Text('Cobrar en efectivo'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Total a cobrar: ${_dinero(widget.totalCentavos)}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Monto recibido (opcional)',
              prefixText: '\$ ',
              errorText: texto.isNotEmpty && !lectura.valido
                  ? (lectura.recibido == null ? 'Monto inválido' : 'No cubre el total')
                  : null,
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (cambio != null && cambio >= 0) ...[
            const SizedBox(height: 12),
            Text('Cambio: ${_dinero(cambio)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _cliente,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'N.º de cliente (opcional, para puntos)',
              errorText: !cliente.valido ? 'Número de cliente inválido' : null,
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (cliente.id != null && cliente.valido) ...[
            const SizedBox(height: 8),
            Text(
              puntos > 0 ? 'Cliente ganará $puntos punto(s)' : 'La compra no alcanza para ganar puntos',
              style: TextStyle(color: Colors.green.shade800, fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: lectura.valido && cliente.valido
              ? () => Navigator.pop(context, (recibido: lectura.recibido, clienteId: cliente.id))
              : null,
          child: const Text('Confirmar venta'),
        ),
      ],
    );
  }
}
