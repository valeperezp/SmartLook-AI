import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../../core/config/env.dart';
import '../../../encargado/mi_qr/models/sucursal_qr.dart';

class QrMostrarWidget extends StatefulWidget {
  final String urlComprobante;
  final SucursalQR? qrSucursal;

  const QrMostrarWidget({
    super.key,
    required this.urlComprobante,
    this.qrSucursal,
  });

  @override
  State<QrMostrarWidget> createState() => _QrMostrarWidgetState();
}

class _QrMostrarWidgetState extends State<QrMostrarWidget> {
  int _modo = 0; // 0: QR dinámico para subir comprobante, 1: QR estático de sucursal

  String _resolverUrl(String? url) {
    if (url == null || url.isEmpty) return '';
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    if (url.startsWith('/')) return '${Env.apiUrl}$url';
    return '${Env.apiUrl}/$url';
  }

  @override
  Widget build(BuildContext context) {
    final tieneQrSucursal = widget.qrSucursal != null && widget.qrSucursal!.activo;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (tieneQrSucursal) ...[
          // Segmented button para alternar entre QR dinámico y QR de sucursal
          SegmentedButton<int>(
            segments: const [
              ButtonSegment<int>(
                value: 0,
                label: Text('Subir Comprobante', style: TextStyle(fontSize: 12)),
                icon: Icon(Icons.qr_code_scanner, size: 16),
              ),
              ButtonSegment<int>(
                value: 1,
                label: Text('QR Sucursal', style: TextStyle(fontSize: 12)),
                icon: Icon(Icons.account_balance, size: 16),
              ),
            ],
            selected: {_modo},
            onSelectionChanged: (newSelection) {
              setState(() {
                _modo = newSelection.first;
              });
            },
          ),
          const SizedBox(height: 16),
        ],

        // Contenedor del código QR
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
          ),
          child: _modo == 0 || !tieneQrSucursal
              ? QrImageView(
                  data: widget.urlComprobante,
                  version: QrVersions.auto,
                  size: 220,
                  backgroundColor: Colors.white,
                )
              : ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    _resolverUrl(widget.qrSucursal?.imagenUrl),
                    width: 220,
                    height: 220,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => Container(
                      width: 220,
                      height: 220,
                      color: Colors.grey.shade100,
                      child: const Center(
                        child: Text(
                          'No se pudo cargar QR de sucursal',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ),
                    ),
                  ),
                ),
        ),
        const SizedBox(height: 12),

        Text(
          _modo == 0 || !tieneQrSucursal
              ? 'El cliente escanea este QR para cargar su comprobante desde su celular.'
              : 'Código QR bancario/billetera oficial de la sucursal para transferir.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
        ),
      ],
    );
  }
}
