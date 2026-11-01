import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../auth/providers/auth_provider.dart';
import '../data/turno_caja_dao.dart';
import '../providers/turno_caja_provider.dart';
import '../providers/venta_offline_provider.dart';
import '../widgets/banner_offline.dart';

String _dinero(int centavos) {
  final signo = centavos < 0 ? '-' : '';
  return '$signo\$${(centavos.abs() / 100).toStringAsFixed(2)}';
}

String _hora(DateTime f) => '${f.hour.toString().padLeft(2, '0')}:${f.minute.toString().padLeft(2, '0')}';

/// Mi Caja: abrir turno con el monto inicial, ver el arqueo en curso y cerrar caja (CU18). Todo en SQLite.
class PantallaTurno extends StatefulWidget {
  const PantallaTurno({super.key});

  @override
  State<PantallaTurno> createState() => _PantallaTurnoState();
}

class _PantallaTurnoState extends State<PantallaTurno> {
  final _montoInicial = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final usuario = context.read<AuthProvider>().usuario;
      final sucursalId = usuario?.sucursalId;
      if (usuario != null && sucursalId != null) context.read<TurnoCajaProvider>().cargar(usuario.id, sucursalId);
    });
  }

  @override
  void dispose() {
    _montoInicial.dispose();
    super.dispose();
  }

  void _avisar(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(mensaje)));
  }

  Future<void> _abrir() async {
    final usuario = context.read<AuthProvider>().usuario;
    final sucursalId = usuario?.sucursalId;
    if (usuario == null || sucursalId == null) return;
    final provider = context.read<TurnoCajaProvider>();
    final ok = await provider.abrir(cajeroId: usuario.id, sucursalId: sucursalId, montoTexto: _montoInicial.text);
    if (!mounted) return;
    if (ok) {
      _montoInicial.clear();
      _avisar('Caja abierta.');
    } else {
      _avisar(provider.error ?? 'No se pudo abrir la caja.');
    }
  }

  Future<void> _cerrar() async {
    final provider = context.read<TurnoCajaProvider>();
    final texto = await showDialog<String>(
      context: context,
      builder: (_) => _MontoContadoDialog(esperadoCentavos: provider.esperadoCentavos),
    );
    if (texto == null || !mounted) return; // canceló

    var resultado = await provider.cerrar(texto);
    if (!mounted) return;
    if (resultado == ResultadoCierre.requiereConfirmacion) {
      final n = provider.pendientesAlCerrar;
      final seguir = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          icon: const Icon(Icons.warning_amber, color: Colors.orange, size: 40),
          title: const Text('Operaciones sin sincronizar'),
          content: Text(
            'Hay $n operación(es) (ventas o cambios/devoluciones) de este turno que todavía no se enviaron al servidor.\n\n'
            'Puedes cerrar igual: el cierre se enviará después de ellas, cuando haya conexión.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cerrar igualmente')),
          ],
        ),
      );
      if (seguir != true || !mounted) return;
      resultado = await provider.cerrar(texto, confirmarPendientes: true);
      if (!mounted) return;
    }
    if (resultado == ResultadoCierre.error) _avisar(provider.error ?? 'No se pudo cerrar la caja.');
  }

  @override
  Widget build(BuildContext context) {
    final usuario = context.watch<AuthProvider>().usuario;
    final provider = context.watch<TurnoCajaProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Mi Caja')),
      body: Column(
        children: [
          const BannerOffline(),
          Expanded(
            child: usuario?.sucursalId == null
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Tu usuario no tiene una sucursal asignada. Pídele a un administrador que te asigne una.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : provider.cargando && provider.turno == null
                    ? const Center(child: CircularProgressIndicator())
                    : provider.turno == null
                        ? _sinTurno(provider)
                        : _turnoAbierto(provider),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------

  Widget _sinTurno(TurnoCajaProvider provider) {
    final texto = _montoInicial.text.trim();
    final problema = texto.isEmpty ? null : TurnoCajaProvider.validarMonto(texto);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (provider.ultimoCierre != null) ...[
          _TarjetaArqueo(arqueo: provider.ultimoCierre!, alDescartar: provider.descartarCierre),
          const SizedBox(height: 16),
        ],
        if (provider.error != null && provider.ultimoCierre == null)
          Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(provider.error!, style: const TextStyle(color: Colors.red))),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Abrir Caja', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text('Ingresa el efectivo con el que empiezas el turno.'),
                const SizedBox(height: 12),
                TextField(
                  controller: _montoInicial,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: 'Monto inicial', prefixText: '\$ ', errorText: problema),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: provider.guardando || texto.isEmpty || problema != null ? null : _abrir,
                    icon: const Icon(Icons.lock_open),
                    label: const Text('ABRIR CAJA', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _turnoAbierto(TurnoCajaProvider provider) {
    final turno = provider.turno!;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Caja abierta a las ${_hora(turno.fechaApertura)}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  _fila('Monto inicial', _dinero(turno.montoInicialCentavos)),
                  _fila('Ventas en efectivo (${provider.ventas.length})', _dinero(provider.totalVentasCentavos)),
                  if (provider.devolucionesNetoCentavos != 0)
                    _fila('Cambios y devoluciones (neto)', _dinero(provider.devolucionesNetoCentavos)),
                  const Divider(),
                  _fila('MONTO ESPERADO', _dinero(provider.esperadoCentavos), grande: true),
                  if (provider.pendientesSync > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        children: [
                          const Icon(Icons.cloud_off, size: 16, color: Colors.orange),
                          const SizedBox(width: 6),
                          Expanded(child: Text('${provider.pendientesSync} operación(es) pendiente(s) de sincronizar')),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('Ventas del turno', style: Theme.of(context).textTheme.titleMedium),
          ),
        ),
        Expanded(
          child: provider.ventas.isEmpty
              ? const Center(child: Text('Todavía no hay ventas en este turno'))
              : ListView.builder(
                  itemCount: provider.ventas.length,
                  itemBuilder: (context, i) {
                    final v = provider.ventas[i];
                    return ListTile(
                      dense: true,
                      leading: Icon(v.sincronizada ? Icons.cloud_done : Icons.cloud_upload_outlined,
                          color: v.sincronizada ? Colors.green : Colors.orange),
                      title: Text(_dinero(v.totalCentavos), style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('${_hora(v.fecha)} · ${v.sincronizada ? "sincronizada" : "pendiente de sincronizar"}'),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
              onPressed: provider.guardando ? null : _cerrar,
              icon: const Icon(Icons.lock),
              label: const Text('CERRAR CAJA', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _fila(String etiqueta, String valor, {bool grande = false}) {
    final estilo = TextStyle(fontSize: grande ? 20 : 15, fontWeight: grande ? FontWeight.bold : FontWeight.w500);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [Expanded(child: Text(etiqueta, style: estilo)), Text(valor, style: estilo)]),
    );
  }
}

/// Arqueo ya cerrado: verde si sobra, rojo si falta.
class _TarjetaArqueo extends StatelessWidget {
  const _TarjetaArqueo({required this.arqueo, required this.alDescartar});

  final ResultadoArqueo arqueo;
  final VoidCallback alDescartar;

  @override
  Widget build(BuildContext context) {
    final d = arqueo.diferenciaCentavos;
    final color = d < 0 ? Colors.red.shade700 : (d > 0 ? Colors.green.shade700 : Colors.blueGrey.shade700);
    final titulo = d < 0 ? 'FALTANTE' : (d > 0 ? 'SOBRANTE' : 'CAJA CUADRADA');
    return Card(
      color: color.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: color, width: 2)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(d < 0 ? Icons.trending_down : (d > 0 ? Icons.trending_up : Icons.check_circle), color: color),
                const SizedBox(width: 8),
                Expanded(child: Text('Caja cerrada · $titulo', style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16))),
                IconButton(onPressed: alDescartar, icon: const Icon(Icons.close), tooltip: 'Ocultar'),
              ],
            ),
            Text('Esperado: ${_dinero(arqueo.esperadoCentavos)}'),
            Text('Contado: ${_dinero(arqueo.realCentavos)}'),
            const SizedBox(height: 4),
            Text('Diferencia: ${d > 0 ? "+" : ""}${_dinero(d)}',
                style: TextStyle(color: color, fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text('El cierre se enviará al servidor cuando haya conexión.', style: TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

/// Pide el efectivo contado y muestra la diferencia contra lo esperado mientras se escribe.
class _MontoContadoDialog extends StatefulWidget {
  const _MontoContadoDialog({required this.esperadoCentavos});

  final int esperadoCentavos;

  @override
  State<_MontoContadoDialog> createState() => _MontoContadoDialogState();
}

class _MontoContadoDialogState extends State<_MontoContadoDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final texto = _controller.text.trim();
    final problema = texto.isEmpty ? null : TurnoCajaProvider.validarMonto(texto);
    final real = texto.isEmpty ? null : VentaOfflineProvider.parseMonto(texto);
    final diferencia = real == null ? null : real - widget.esperadoCentavos;
    final color = diferencia == null
        ? null
        : (diferencia < 0 ? Colors.red.shade700 : (diferencia > 0 ? Colors.green.shade700 : Colors.blueGrey));

    return AlertDialog(
      title: const Text('Cerrar caja'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Monto esperado: ${_dinero(widget.esperadoCentavos)}', style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'Monto contado', prefixText: '\$ ', errorText: problema),
            onChanged: (_) => setState(() {}),
          ),
          if (diferencia != null) ...[
            const SizedBox(height: 12),
            Text(
              diferencia == 0
                  ? 'Caja cuadrada'
                  : '${diferencia < 0 ? "Faltante" : "Sobrante"}: ${_dinero(diferencia.abs())}',
              style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: texto.isNotEmpty && problema == null ? () => Navigator.pop(context, texto) : null,
          child: const Text('Cerrar caja'),
        ),
      ],
    );
  }
}
