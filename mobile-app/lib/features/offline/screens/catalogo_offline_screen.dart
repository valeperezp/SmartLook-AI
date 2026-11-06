import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../auth/providers/auth_provider.dart';
import '../models/catalogo_item.dart';
import '../providers/catalogo_offline_provider.dart';
import '../providers/suscripciones_provider.dart';
import '../services/sync_service.dart';
import '../widgets/banner_offline.dart';

/// Catálogo leído de SQLite (funciona sin red) con reserva local de productos.
class CatalogoOfflineScreen extends StatefulWidget {
  const CatalogoOfflineScreen({super.key});

  @override
  State<CatalogoOfflineScreen> createState() => _CatalogoOfflineScreenState();
}

class _CatalogoOfflineScreenState extends State<CatalogoOfflineScreen> {
  StreamSubscription<ResultadoSync>? _autoSync;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<CatalogoOfflineProvider>().cargar();
      _cargarSuscripciones();
      // Sincronización automática: refresca el catálogo (un rechazo devuelve stock) y avisa
      _autoSync = context.read<SyncService>().alSincronizarAutomaticamente.listen((r) {
        if (!mounted) return;
        context.read<CatalogoOfflineProvider>().cargar();
        _avisar('Sincronización automática: ${r.resumen}');
        _revisarAvisos();
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
      ..showSnackBar(SnackBar(content: Text(mensaje)));
  }

  Future<void> _reservar(CatalogoItem producto) async {
    final provider = context.read<CatalogoOfflineProvider>();
    final clienteId = context.read<AuthProvider>().usuario?.id;
    if (clienteId == null) {
      _avisar('Inicia sesión para reservar.');
      return;
    }
    await provider.reservarProducto(producto, clienteId);
    _avisar(provider.ultimoMensaje);
  }

  Future<void> _cargarMock({bool reponerAgotados = false}) async {
    final provider = context.read<CatalogoOfflineProvider>();
    await provider.cargarDatosMock(reponerAgotados: reponerAgotados);
    _avisar(provider.ultimoMensaje);
    await _revisarAvisos();
  }

  /// Descarga el catálogo real del backend. Sin red se queda con el catálogo local y lo avisa.
  Future<void> _actualizarCatalogo() async {
    final provider = context.read<CatalogoOfflineProvider>();
    await provider.actualizarDesdeServidor();
    _avisar(provider.ultimoMensaje);
    await _revisarAvisos();
  }

  int? get _clienteId => context.read<AuthProvider>().usuario?.id;

  Future<void> _cargarSuscripciones() async {
    final clienteId = _clienteId;
    if (clienteId == null) return;
    await context.read<SuscripcionesProvider>().cargar(clienteId);
    await _revisarAvisos();
  }

  /// CU16: si llegó stock de algo que el cliente esperaba, se lo dice.
  Future<void> _revisarAvisos() async {
    final clienteId = _clienteId;
    if (clienteId == null || !mounted) return;
    final mensajes = await context.read<SuscripcionesProvider>().revisarAvisos(clienteId);
    if (mensajes.isEmpty || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(mensajes.join('\n')),
        duration: const Duration(seconds: 6),
        backgroundColor: Colors.green.shade800,
      ));
  }

  Future<void> _avisame(CatalogoItem producto) async {
    final clienteId = _clienteId;
    if (clienteId == null) {
      _avisar('Inicia sesión para recibir avisos.');
      return;
    }
    final suscripciones = context.read<SuscripcionesProvider>();
    await suscripciones.suscribirse(producto, clienteId);
    _avisar(suscripciones.mensaje);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CatalogoOfflineProvider>();
    // Se observa aquí (no dentro del itemBuilder): context.select/watch no se permite en un builder diferido.
    final suscripciones = context.watch<SuscripcionesProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Catálogo offline'),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_circle),
            tooltip: 'Mi cuenta (puntos y avisos)',
            onPressed: () => context.push('/offline/mi-cuenta'),
          ),
          if (kDebugMode && provider.soportado)
            IconButton(
              icon: const Icon(Icons.local_shipping),
              tooltip: 'Simular llegada de stock (debug)',
              onPressed: provider.cargando ? null : () => _cargarMock(reponerAgotados: true),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar catálogo',
            onPressed: provider.cargando ? null : _actualizarCatalogo,
          ),
        ],
      ),
      floatingActionButton: kDebugMode && provider.soportado
          ? FloatingActionButton.extended(
              onPressed: provider.cargando ? null : _cargarMock,
              icon: const Icon(Icons.dataset),
              label: const Text('Cargar Datos Mock'),
            )
          : null,
      body: Column(
        children: [
          const BannerOffline(),
          if (provider.pendientes > 0)
            Container(
              width: double.infinity,
              color: Colors.amber.shade100,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.cloud_off, size: 18, color: Colors.amber.shade900),
                  const SizedBox(width: 8),
                  Text('${provider.pendientes} reserva(s) pendiente(s) de sincronizar', style: TextStyle(color: Colors.amber.shade900, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          Expanded(child: _cuerpo(provider, suscripciones)),
        ],
      ),
    );
  }

  Widget _cuerpo(CatalogoOfflineProvider provider, SuscripcionesProvider suscripciones) {
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
            'No hay catálogo guardado en el dispositivo.\nToca el botón de actualizar para descargarlo.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 88), // espacio para el botón flotante
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.62,
      ),
      itemCount: provider.productos.length,
      itemBuilder: (context, i) {
        final producto = provider.productos[i];
        return _TarjetaProducto(
          producto: producto,
          reservando: provider.estaReservando(producto),
          suscrito: suscripciones.estaSuscrito(producto),
          onReservar: () => _reservar(producto),
          onAvisame: () => _avisame(producto),
        );
      },
    );
  }
}

class _TarjetaProducto extends StatelessWidget {
  const _TarjetaProducto({
    required this.producto,
    required this.reservando,
    required this.suscrito,
    required this.onReservar,
    required this.onAvisame,
  });

  final CatalogoItem producto;
  final bool reservando;

  /// El cliente ya pidió que le avisen cuando llegue esta prenda.
  final bool suscrito;
  final VoidCallback onReservar;
  final VoidCallback onAvisame;

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final colorStock = !producto.hayStock
        ? esquema.error
        : producto.cantidadDisponible <= 3
            ? Colors.orange.shade800
            : Colors.green.shade700;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _imagen()),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(producto.nombre, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                if (producto.variante.isNotEmpty)
                  Text(producto.variante, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 4),
                Text(producto.precioTexto, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                Text(
                  producto.hayStock ? 'Stock: ${producto.cantidadDisponible}' : 'Agotado',
                  style: TextStyle(color: colorStock, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: SizedBox(
              width: double.infinity,
              child: producto.hayStock
                  ? FilledButton(
                      onPressed: !reservando ? onReservar : null,
                      child: Text(reservando ? 'Guardando…' : 'Reservar'),
                    )
                  // Sin stock no se puede reservar: se ofrece el aviso (CU16)
                  : OutlinedButton.icon(
                      onPressed: suscrito ? null : onAvisame,
                      icon: Icon(suscrito ? Icons.notifications_active : Icons.notifications_none, size: 18),
                      label: Text(suscrito ? 'Te avisaremos' : 'Avísame cuando llegue', textAlign: TextAlign.center),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _imagen() {
    final placeholder = Container(
      color: Colors.grey.shade200,
      alignment: Alignment.center,
      child: Icon(Icons.checkroom, size: 48, color: Colors.grey.shade500),
    );
    final url = producto.imagenUrl;
    if (url == null || url.isEmpty) return placeholder;
    return Image.network(url, fit: BoxFit.cover, width: double.infinity,
        errorBuilder: (_, _, _) => placeholder);
  }
}
