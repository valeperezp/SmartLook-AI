import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/config/regla_puntos.dart';

/// Lo que el cajero eligió: el cliente (si lo hay) y cuántos puntos canjea como descuento.
typedef SeleccionPuntos = ({int? clienteId, bool valido, int puntos});

String _dinero(int centavos) => '\$${(centavos / 100).toStringAsFixed(2)}';

/// Cliente + canje de puntos (CU17) al cobrar: el cajero escribe el N.º de cliente, la app consulta su saldo y, si tiene
/// puntos, ofrece "Usar N puntos (descuento $X)". Solo se pueden usar los puntos que tiene y sin que el descuento pase del
/// total. La regla "cuánto vale un punto" sale de [ReglaPuntos] (que viene del backend).
class SelectorCanjePuntos extends StatefulWidget {
  const SelectorCanjePuntos({
    super.key,
    required this.totalCentavos,
    required this.consultarSaldo,
    required this.alCambiar,
  });

  /// Total de la compra ANTES del descuento por puntos.
  final int totalCentavos;

  /// Saldo disponible del cliente (del servidor, o el local si no hay red). Si lanza, no se ofrece el canje.
  final Future<int> Function(int clienteId) consultarSaldo;
  final ValueChanged<SeleccionPuntos> alCambiar;

  @override
  State<SelectorCanjePuntos> createState() => _SelectorCanjePuntosState();
}

class _SelectorCanjePuntosState extends State<SelectorCanjePuntos> {
  final _cliente = TextEditingController();
  Timer? _espera;
  int? _saldo;
  bool _consultando = false;
  bool _usar = false;

  /// Vacío = venta sin cliente (válido). Un entero positivo = cliente registrado. Otra cosa = inválido.
  ({bool valido, int? id}) get _lecturaCliente {
    final texto = _cliente.text.trim();
    if (texto.isEmpty) return (valido: true, id: null);
    final id = RegExp(r'^\d{1,9}$').hasMatch(texto) ? int.parse(texto) : null;
    return (valido: id != null && id > 0, id: id);
  }

  int get _usables => ReglaPuntos.puntosUsables(saldo: _saldo ?? 0, totalCentavos: widget.totalCentavos);
  int get _puntos => _usar ? _usables : 0;

  @override
  void dispose() {
    _espera?.cancel();
    _cliente.dispose();
    super.dispose();
  }

  void _notificar() {
    final c = _lecturaCliente;
    widget.alCambiar((clienteId: c.id, valido: c.valido, puntos: _puntos));
  }

  void _alEscribir(String _) {
    _espera?.cancel();
    setState(() {
      _saldo = null;
      _usar = false;
      _consultando = false;
    });
    _notificar();
    final c = _lecturaCliente;
    if (c.id == null || !c.valido) return;
    _espera = Timer(const Duration(milliseconds: 400), () => _consultar(c.id!));
  }

  Future<void> _consultar(int clienteId) async {
    setState(() => _consultando = true);
    int? saldo;
    try {
      saldo = await widget.consultarSaldo(clienteId);
    } catch (_) {
      saldo = null; // sin red ni datos locales: no se ofrece el canje, la venta sigue normal
    }
    if (!mounted || _lecturaCliente.id != clienteId) return; // el cajero ya cambió el número
    setState(() {
      _saldo = saldo;
      _consultando = false;
    });
    _notificar();
  }

  @override
  Widget build(BuildContext context) {
    final cliente = _lecturaCliente;
    final usables = _usables;
    final descuento = ReglaPuntos.descuentoCentavos(usables);
    final verde = Colors.green.shade800;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _cliente,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'N.º de cliente (opcional, para puntos)',
            errorText: !cliente.valido ? 'Número de cliente inválido' : null,
          ),
          onChanged: _alEscribir,
        ),
        if (cliente.id != null && cliente.valido) ...[
          const SizedBox(height: 8),
          if (_consultando)
            const Text('Consultando puntos…')
          else if (_saldo == null)
            const Text('No se pudo consultar el saldo de puntos.')
          else ...[
            Text(
              'Puntos disponibles: $_saldo (valen ${_dinero(ReglaPuntos.descuentoCentavos(_saldo!))})',
              style: TextStyle(color: verde, fontWeight: FontWeight.w600),
            ),
            if (usables > 0)
              CheckboxListTile(
                key: const Key('canjear_puntos'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _usar,
                onChanged: (v) {
                  setState(() => _usar = v ?? false);
                  _notificar();
                },
                title: Text('Usar $usables puntos (Descuento: ${_dinero(descuento)})'),
              )
            else if (_saldo! > 0)
              const Text('El total no alcanza para canjear un punto.'),
            Text(
              ReglaPuntos.puntosPara(widget.totalCentavos - ReglaPuntos.descuentoCentavos(_puntos)) > 0
                  ? 'Cliente ganará ${ReglaPuntos.puntosPara(widget.totalCentavos - ReglaPuntos.descuentoCentavos(_puntos))} punto(s)'
                  : 'La compra no alcanza para ganar puntos',
              style: TextStyle(color: verde),
            ),
          ],
        ],
      ],
    );
  }
}
