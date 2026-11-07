import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/services/devoluciones_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/catalogo_item.dart';
import '../models/devolucion_models.dart';
import '../providers/devolucion_provider.dart';
import '../providers/turno_caja_provider.dart';
import '../widgets/banner_offline.dart';

String _dinero(int centavos) {
  final signo = centavos < 0 ? '-' : '';
  return '$signo\$${(centavos.abs() / 100).toStringAsFixed(2)}';
}

String _fecha(DateTime f) =>
    '${f.day.toString().padLeft(2, '0')}/${f.month.toString().padLeft(2, '0')} '
    '${f.hour.toString().padLeft(2, '0')}:${f.minute.toString().padLeft(2, '0')}';

/// Cambios y devoluciones del cajero (CU11), sin conexión: busca la venta, elige qué vuelve y qué se lleva el cliente.
class PantallaDevoluciones extends StatefulWidget {
  const PantallaDevoluciones({super.key});

  @override
  State<PantallaDevoluciones> createState() => _PantallaDevolucionesState();
}

class _PantallaDevolucionesState extends State<PantallaDevoluciones> {
  final _busqueda = TextEditingController();
  final _motivo = TextEditingController();

  int? get _sucursalId => context.read<AuthProvider>().usuario?.sucursalId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final usuario = context.read<AuthProvider>().usuario;
      final sucursalId = usuario?.sucursalId;
      if (usuario == null || sucursalId == null) return;
      context.read<DevolucionProvider>()
        ..limpiar()
        ..buscar(sucursalId)
        ..cargarCatalogo(sucursalId);
      context.read<TurnoCajaProvider>().cargar(usuario.id, sucursalId);
      // El plazo de días lo define el backend: se descarga (si hay red) para la estimación sin conexión
      DevolucionesService().sincronizarPlazo().then((_) {
        if (mounted) setState(() {});
      }).catchError((Object _) {});
    });
  }

  @override
  void dispose() {
    _busqueda.dispose();
    _motivo.dispose();
    super.dispose();
  }

  void _avisar(String? mensaje) {
    if (mensaje == null || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(mensaje)));
  }

  Future<void> _buscar() async {
    final sucursalId = _sucursalId;
    if (sucursalId == null) return;
    final provider = context.read<DevolucionProvider>();
    await provider.buscar(sucursalId, texto: _busqueda.text);
    _avisar(provider.mensaje);
  }

  Future<void> _abrirVenta(VentaLocal v) async {
    final provider = context.read<DevolucionProvider>();
    if (!await provider.seleccionarVenta(v.uuid)) _avisar(provider.mensaje);
  }

  Future<void> _confirmar() async {
    final provider = context.read<DevolucionProvider>();
    final turno = context.read<TurnoCajaProvider>().turno;
    if (turno == null) {
      _avisar('Abre tu caja para registrar cambios y devoluciones.');
      return;
    }
    final diferencia = provider.diferenciaCentavos;
    final esCambio = provider.tipo == 'CAMBIO';
    final seguir = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(esCambio ? 'Confirmar cambio' : 'Confirmar devolución'),
        content: Text(_textoDiferencia(diferencia, esCambio)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Volver')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirmar')),
        ],
      ),
    );
    if (seguir != true || !mounted) return;

    final resultado = await provider.confirmar(turnoUuid: turno.id, motivo: _motivo.text);
    if (!mounted) return;
    if (resultado == null) {
      _avisar(provider.mensaje);
      return;
    }
    _motivo.clear();
    final sucursalId = _sucursalId;
    final turnos = context.read<TurnoCajaProvider>();
    await turnos.refrescar(); // el efectivo esperado del turno cambió
    if (!mounted) return;
    if (sucursalId != null) {
      provider
        ..buscar(sucursalId)
        ..cargarCatalogo(sucursalId);
    }
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        icon: const Icon(Icons.check_circle, color: Colors.green, size: 48),
        title: const Text('Registrado'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Guardado localmente. Pendiente de sincronizar.', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Text(_textoDiferencia(resultado.diferenciaCentavos, esCambio), textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Aceptar'))],
      ),
    );
  }

  static String _textoDiferencia(int diferencia, bool esCambio) {
    if (diferencia > 0) return 'El cliente debe pagar ${_dinero(diferencia)}';
    if (diferencia < 0) return 'Debes devolver ${_dinero(-diferencia)} al cliente';
    return esCambio ? 'Cambio sin diferencia de dinero' : 'Sin dinero que devolver';
  }

  @override
  Widget build(BuildContext context) {
    final usuario = context.watch<AuthProvider>().usuario;
    final provider = context.watch<DevolucionProvider>();
    final turno = context.watch<TurnoCajaProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cambios y devoluciones'),
        leading: provider.venta == null ? null : IconButton(icon: const Icon(Icons.arrow_back), onPressed: provider.limpiar),
      ),
      body: Column(
        children: [
          const BannerOffline(),
          if (usuario?.sucursalId != null && !turno.cargando && !turno.hayTurnoAbierto) _avisoSinCaja(),
          Expanded(
            child: usuario?.sucursalId == null
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Tu usuario no tiene una sucursal asignada. Pídele a un administrador que te asigne una.', textAlign: TextAlign.center),
                    ),
                  )
                : provider.venta == null
                    ? _listaVentas(provider)
                    : _detalle(provider, turno),
          ),
        ],
      ),
    );
  }

  Widget _avisoSinCaja() {
    return Container(
      width: double.infinity,
      color: Colors.amber.shade100,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.lock, size: 18, color: Colors.amber.shade900),
          const SizedBox(width: 8),
          Expanded(child: Text('Tu caja está cerrada: ábrela para registrar cambios y devoluciones.', style: TextStyle(color: Colors.amber.shade900))),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.brown.shade800),
            onPressed: () => context.push('/offline/turno'),
            child: const Text('Abrir caja', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _listaVentas(DevolucionProvider provider) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _busqueda,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              labelText: 'UUID de la venta o número de recibo',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward), tooltip: 'Buscar', onPressed: _buscar),
            ),
            onSubmitted: (_) => _buscar(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(_busqueda.text.trim().isEmpty ? 'Ventas recientes' : 'Resultados', style: Theme.of(context).textTheme.titleSmall),
          ),
        ),
        Expanded(
          child: provider.cargando && provider.ventas.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : provider.ventas.isEmpty
                  ? const Center(child: Text('No hay ventas para mostrar'))
                  : ListView.builder(
                      itemCount: provider.ventas.length,
                      itemBuilder: (context, i) {
                        final v = provider.ventas[i];
                        final enPlazo = v.dentroDePlazo(provider.plazoDias);
                        // El plazo es solo una estimación del dispositivo: no se bloquea, el servidor decide al sincronizar
                        return ListTile(
                          leading: const Icon(Icons.receipt_long),
                          title: Text('Recibo ${v.recibo} · ${_dinero(v.totalCentavos)}'),
                          subtitle: Text(enPlazo ? _fecha(v.fecha) : '${_fecha(v.fecha)} · posiblemente fuera de plazo (${provider.plazoDias} días)'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _abrirVenta(v),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _detalle(DevolucionProvider provider, TurnoCajaProvider turno) {
    final venta = provider.venta!;
    final diferencia = provider.diferenciaCentavos;
    final esCambio = provider.tipo == 'CAMBIO';
    final color = diferencia > 0 ? Colors.blue.shade800 : (diferencia < 0 ? Colors.red.shade700 : Colors.blueGrey);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text('Venta ${venta.recibo} · ${_fecha(venta.fecha)} · ${_dinero(venta.totalCentavos)}', style: const TextStyle(fontWeight: FontWeight.bold)),
        if (provider.avisoPlazo != null) ...[
          const SizedBox(height: 8),
          Container(
            key: const Key('aviso_plazo'),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.amber.shade100, borderRadius: BorderRadius.circular(8)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.schedule, size: 18, color: Colors.amber.shade900),
                const SizedBox(width: 8),
                Expanded(child: Text(provider.avisoPlazo!, style: TextStyle(color: Colors.amber.shade900, fontSize: 12.5))),
              ],
            ),
          ),
        ],
        const SizedBox(height: 8),
        Text('Prendas que devuelve el cliente', style: Theme.of(context).textTheme.titleSmall),
        for (final item in venta.items) _filaDevuelto(provider, item),
        const Divider(height: 24),
        Row(
          children: [
            Expanded(child: Text('Prendas nuevas (cambio)', style: Theme.of(context).textTheme.titleSmall)),
            OutlinedButton.icon(onPressed: () => _elegirPrendaNueva(provider), icon: const Icon(Icons.add), label: const Text('Agregar')),
          ],
        ),
        if (provider.nuevos.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Sin prendas nuevas: será una devolución.')),
        for (final l in provider.nuevos) _filaNueva(provider, l),
        const Divider(height: 24),
        Card(
          color: color.withValues(alpha: 0.08),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _fila('Total devuelto', _dinero(provider.totalDevueltoCentavos)),
                _fila('Total nuevo', _dinero(provider.totalNuevoCentavos)),
                const Divider(),
                Text(_textoDiferencia(diferencia, esCambio), style: TextStyle(color: color, fontSize: 19, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(controller: _motivo, decoration: const InputDecoration(labelText: 'Motivo (opcional)'), textCapitalization: TextCapitalization.sentences),
        const SizedBox(height: 16),
        SizedBox(
          height: 54,
          child: FilledButton.icon(
            onPressed: provider.puedeConfirmar && turno.hayTurnoAbierto ? _confirmar : null,
            icon: provider.guardando ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.swap_horiz),
            label: Text(esCambio ? 'CONFIRMAR CAMBIO' : 'CONFIRMAR DEVOLUCIÓN', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ),
        if (!turno.hayTurnoAbierto)
          const Padding(padding: EdgeInsets.only(top: 8), child: Text('Necesitas una caja abierta para confirmar.', textAlign: TextAlign.center)),
      ],
    );
  }

  Widget _fila(String etiqueta, String valor) =>
      Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Row(children: [Expanded(child: Text(etiqueta)), Text(valor, style: const TextStyle(fontWeight: FontWeight.w600))]));

  Widget _filaDevuelto(DevolucionProvider provider, ItemVentaLocal item) {
    final n = provider.cantidadADevolver(item);
    final agotado = item.devolvible <= 0;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(item.nombre, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('${_dinero(item.precioCentavos)} c/u · vendidas ${item.cantidad}'
          '${item.devuelta > 0 ? ' · ya devueltas ${item.devuelta}' : ''}'),
      trailing: agotado
          ? const Text('Devuelta')
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: n > 0 ? () => provider.cambiarDevolucion(item, -1) : null),
                Text('$n', style: const TextStyle(fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: n < item.devolvible ? () => provider.cambiarDevolucion(item, 1) : null),
              ],
            ),
    );
  }

  Widget _filaNueva(DevolucionProvider provider, LineaNueva l) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(l.producto.nombre, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('${l.producto.variante.isEmpty ? '' : '${l.producto.variante} · '}${l.producto.precioTexto} c/u'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: () => provider.quitarNuevo(l.producto)),
          Text('${l.cantidad}', style: const TextStyle(fontWeight: FontWeight.bold)),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: provider.disponibleParaAgregar(l.producto) > 0 ? () => provider.agregarNuevo(l.producto) : null,
          ),
        ],
      ),
    );
  }

  Future<void> _elegirPrendaNueva(DevolucionProvider provider) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ChangeNotifierProvider<DevolucionProvider>.value(
        value: provider,
        child: const _SelectorPrenda(),
      ),
    );
  }
}

/// Hoja con el catálogo local para elegir las prendas nuevas del cambio.
class _SelectorPrenda extends StatelessWidget {
  const _SelectorPrenda();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DevolucionProvider>();
    final prendas = provider.catalogo;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          children: [
            const Padding(padding: EdgeInsets.all(12), child: Text('Elige la prenda nueva', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
            Expanded(
              child: prendas.isEmpty
                  ? const Center(child: Text('No hay catálogo local en esta sucursal'))
                  : ListView.builder(
                      itemCount: prendas.length,
                      itemBuilder: (context, i) => _Opcion(prenda: prendas[i]),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(width: double.infinity, child: FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Listo'))),
            ),
          ],
        ),
      ),
    );
  }
}

class _Opcion extends StatelessWidget {
  const _Opcion({required this.prenda});

  final CatalogoItem prenda;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DevolucionProvider>();
    final restante = provider.disponibleParaAgregar(prenda);
    final enCambio = provider.cantidadNueva(prenda);
    return ListTile(
      enabled: restante > 0,
      title: Text(prenda.nombre),
      subtitle: Text('${prenda.variante.isEmpty ? '' : '${prenda.variante} · '}${prenda.precioTexto} · ${restante > 0 ? 'Stock: $restante' : 'Agotado'}'),
      trailing: enCambio > 0 ? Badge(label: Text('$enCambio')) : const Icon(Icons.add),
      onTap: restante > 0 ? () => provider.agregarNuevo(prenda) : null,
    );
  }
}
