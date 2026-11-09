import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../reservas/widgets/selector_qr.dart';
import '../models/catalogo_item.dart';

/// Lo que el cliente confirmó en la hoja de compra: cuántas unidades y el comprobante de su transferencia.
class CompraQr {
  const CompraQr({required this.cantidad, required this.comprobante, required this.nombreComprobante});

  final int cantidad;
  final Uint8List comprobante;
  final String nombreComprobante;
}

/// Abre la hoja "Comprar" del catálogo offline. Devuelve la compra confirmada, o null si el cliente la cierra.
Future<CompraQr?> mostrarCompraQr(
  BuildContext context, {
  required CatalogoItem producto,
  required Future<Uint8List?> Function() obtenerQr,
  SelectorQr? selector,
  String? motivoSinQr,
}) {
  return showModalBottomSheet<CompraQr>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => CompraQrSheet(producto: producto, obtenerQr: obtenerQr, selector: selector ?? elegirComprobanteConImagePicker, motivoSinQr: motivoSinQr),
  );
}

/// Compra offline con pago por QR: el cliente ve el QR bancario de la sucursal (guardado en el celular), paga con la app de su
/// banco, sube el comprobante y confirma. La compra queda en la cola de sincronización y el stock local baja enseguida.
class CompraQrSheet extends StatefulWidget {
  const CompraQrSheet({super.key, required this.producto, required this.obtenerQr, required this.selector, this.motivoSinQr});

  final CatalogoItem producto;

  /// El QR guardado de la sucursal del producto (null si nunca se descargó).
  final Future<Uint8List?> Function() obtenerQr;
  final SelectorQr selector;

  /// Por qué no hay QR guardado (la última actualización del catálogo lo averiguó): se muestra junto al aviso.
  final String? motivoSinQr;

  @override
  State<CompraQrSheet> createState() => _CompraQrSheetState();
}

class _CompraQrSheetState extends State<CompraQrSheet> {
  int _cantidad = 1;
  Uint8List? _qr;
  bool _cargandoQr = true;
  QrElegido? _comprobante;

  @override
  void initState() {
    super.initState();
    _cargarQr();
  }

  Future<void> _cargarQr() async {
    Uint8List? qr;
    try {
      qr = await widget.obtenerQr();
    } catch (_) {
      qr = null;
    }
    if (!mounted) return;
    setState(() {
      _qr = qr;
      _cargandoQr = false;
    });
  }

  Future<void> _subirComprobante() async {
    final elegido = await widget.selector(context);
    if (elegido == null || !mounted) return;
    setState(() => _comprobante = elegido);
  }

  String get _total => '\$${(widget.producto.precioCentavos * _cantidad / 100).toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    final p = widget.producto;
    final tema = Theme.of(context);
    final maximo = p.cantidadDisponible;

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Comprar sin conexión', style: tema.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(p.nombre, style: const TextStyle(fontWeight: FontWeight.w600)),
            if (p.variante.isNotEmpty) Text(p.variante, style: tema.textTheme.bodySmall),
            const SizedBox(height: 12),
            Row(
              children: [
                IconButton.outlined(
                  key: const Key('menos'),
                  onPressed: _cantidad > 1 ? () => setState(() => _cantidad--) : null,
                  icon: const Icon(Icons.remove),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text('$_cantidad', key: const Key('cantidad'), style: tema.textTheme.titleMedium),
                ),
                IconButton.outlined(
                  key: const Key('mas'),
                  onPressed: _cantidad < maximo ? () => setState(() => _cantidad++) : null,
                  icon: const Icon(Icons.add),
                ),
                const Spacer(),
                Text('Total: $_total', key: const Key('total'), style: tema.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const Divider(height: 28),
            // El único método sin conexión es la transferencia por QR
            Row(
              children: [
                const Icon(Icons.qr_code_2),
                const SizedBox(width: 8),
                Text('Pago por QR', style: tema.textTheme.titleMedium),
                const Spacer(),
                const Icon(Icons.check_circle, color: Colors.green),
              ],
            ),
            const SizedBox(height: 8),
            Text('Escanea este QR con la app de tu banco, paga $_total y sube el comprobante de la transferencia.', style: tema.textTheme.bodyMedium),
            const SizedBox(height: 12),
            Center(child: _bloqueQr()),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              key: const Key('subir_comprobante'),
              onPressed: _subirComprobante,
              icon: const Icon(Icons.upload_file),
              label: Text(_comprobante == null ? 'Subir comprobante' : 'Cambiar comprobante'),
            ),
            if (_comprobante != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(_comprobante!.bytes, key: const Key('vista_comprobante'), width: 72, height: 72, fit: BoxFit.cover),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text('Comprobante listo', style: TextStyle(color: Colors.green.shade800, fontWeight: FontWeight.w600))),
                ],
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('confirmar_compra'),
              onPressed: _comprobante == null
                  ? null
                  : () => Navigator.pop(context, CompraQr(cantidad: _cantidad, comprobante: _comprobante!.bytes, nombreComprobante: _comprobante!.nombre)),
              child: const Text('Confirmar compra'),
            ),
            const SizedBox(height: 6),
            Text(
              'Se guarda en tu celular y se envía cuando vuelva la conexión. El encargado verificará tu comprobante antes de entregarte las prendas.',
              style: tema.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _bloqueQr() {
    if (_cargandoQr) return const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()));
    if (_qr == null) {
      return Container(
        key: const Key('sin_qr'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(10)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Esta sucursal no tiene su QR guardado en el celular. Conéctate a internet una vez y actualiza el catálogo para descargarlo.',
              style: TextStyle(color: Colors.orange.shade900),
            ),
            if (widget.motivoSinQr != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Motivo: ${widget.motivoSinQr}', key: const Key('motivo_sin_qr'), style: TextStyle(color: Colors.orange.shade900, fontWeight: FontWeight.w600)),
              ),
          ],
        ),
      );
    }
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(8),
      child: Image.memory(_qr!, key: const Key('qr_sucursal'), width: 220, height: 220, fit: BoxFit.contain),
    );
  }
}
