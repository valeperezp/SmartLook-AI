import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../../core/config/env.dart';
import '../models/pago.dart';
import '../providers/checkout_provider.dart';

class QrPaymentWidget extends StatefulWidget {
  final int ventaId;
  final double monto;
  final VoidCallback onPagoEnviado;

  const QrPaymentWidget({
    super.key,
    required this.ventaId,
    required this.monto,
    required this.onPagoEnviado,
  });

  @override
  State<QrPaymentWidget> createState() => _QrPaymentWidgetState();
}

class _QrPaymentWidgetState extends State<QrPaymentWidget> {
  final ImagePicker _picker = ImagePicker();

  bool _cargando = true;
  Pago? _pago;
  String? _qrData;
  String? _errorMensaje;

  XFile? _archivoSeleccionado;
  Uint8List? _previewBytes;
  bool _subiendoComprobante = false;

  @override
  void initState() {
    super.initState();
    _iniciarPagoQR();
  }

  Future<void> _iniciarPagoQR() async {
    setState(() {
      _cargando = true;
      _errorMensaje = null;
    });

    final provider = context.read<CheckoutProvider>();
    final pago = await provider.iniciarPagoQR();

    if (!mounted) return;

    if (pago != null) {
      setState(() {
        _pago = pago;
        _qrData = '${Env.webUrl}/pago/${pago.id}/comprobante?monto=${widget.monto}&venta=${widget.ventaId}';
        _cargando = false;
      });
    } else {
      setState(() {
        _errorMensaje = provider.errorMessage ?? 'No se pudo generar el código QR de pago.';
        _cargando = false;
      });
    }
  }

  Future<void> _seleccionarImagen(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );

      if (picked != null) {
        final bytes = await picked.readAsBytes();
        setState(() {
          _archivoSeleccionado = picked;
          _previewBytes = bytes;
          _errorMensaje = null;
        });
      }
    } catch (e) {
      setState(() {
        _errorMensaje = 'Error al seleccionar imagen: $e';
      });
    }
  }

  Future<void> _subirComprobante() async {
    if (_archivoSeleccionado == null) {
      setState(() {
        _errorMensaje = 'Por favor seleccioná o tomá una foto del comprobante.';
      });
      return;
    }

    setState(() {
      _subiendoComprobante = true;
      _errorMensaje = null;
    });

    final provider = context.read<CheckoutProvider>();
    final ok = await provider.subirQRComprobante(_archivoSeleccionado!);

    if (!mounted) return;

    setState(() {
      _subiendoComprobante = false;
    });

    if (ok) {
      widget.onPagoEnviado();
    } else {
      setState(() {
        _errorMensaje = provider.errorMessage ?? 'Error al subir el comprobante.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_cargando) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              const Text('Generando código QR seguro...', style: TextStyle(fontSize: 15)),
            ],
          ),
        ),
      );
    }

    if (_errorMensaje != null && _pago == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Column(
          children: [
            Icon(Icons.error_outline, color: Colors.red.shade700, size: 36),
            const SizedBox(height: 8),
            Text(
              _errorMensaje!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.red.shade800),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () {
                context.read<CheckoutProvider>().resetearCheckout();
                _iniciarPagoQR();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Tarjeta resumen orden QR
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.purple.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.purple.shade200),
          ),
          child: Column(
            children: [
              Text(
                'Orden #${widget.ventaId}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.purple.shade900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '\$${widget.monto.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.purple.shade900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Transferí o pagá escaneando el código QR oficial',
                style: TextStyle(fontSize: 12, color: Colors.purple.shade800),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // QR Code Container
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: QrImageView(
            data: _qrData ?? 'pago:${widget.ventaId}',
            version: QrVersions.auto,
            size: 200.0,
            backgroundColor: Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Pago ID: #${_pago?.id ?? widget.ventaId}',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600, letterSpacing: 1),
        ),
        const SizedBox(height: 24),

        // Sección Comprobante
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.receipt_long, size: 20, color: Colors.black87),
                  SizedBox(width: 8),
                  Text(
                    'Comprobante de Pago',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Una vez realizada la transferencia, subí una captura o foto de la constancia de pago para que la sucursal la valide.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 14),

              if (_previewBytes != null) ...[
                Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.memory(
                      _previewBytes!,
                      height: 160,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton.icon(
                      onPressed: () => _seleccionarImagen(ImageSource.gallery),
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Cambiar imagen'),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _archivoSeleccionado = null;
                          _previewBytes = null;
                        });
                      },
                      icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                      label: const Text('Quitar', style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              ] else ...[
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _seleccionarImagen(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library_outlined, size: 18),
                        label: const Text('Galería'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _seleccionarImagen(ImageSource.camera),
                        icon: const Icon(Icons.camera_alt_outlined, size: 18),
                        label: const Text('Cámara'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],

              if (_errorMensaje != null && _pago != null) ...[
                const SizedBox(height: 10),
                Text(
                  _errorMensaje!,
                  style: TextStyle(color: Colors.red.shade700, fontSize: 13),
                ),
              ],

              const SizedBox(height: 16),

              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _subiendoComprobante || _archivoSeleccionado == null
                      ? null
                      : _subirComprobante,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple.shade700,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: _subiendoComprobante
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.cloud_upload_outlined),
                  label: Text(
                    _subiendoComprobante
                        ? 'Enviando comprobante...'
                        : 'Enviar Comprobante',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
