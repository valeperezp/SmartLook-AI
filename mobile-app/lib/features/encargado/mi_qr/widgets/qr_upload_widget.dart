import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class QrUploadWidget extends StatefulWidget {
  final bool isSubiendo;
  final Function(XFile archivo) onSubir;

  const QrUploadWidget({
    super.key,
    required this.isSubiendo,
    required this.onSubir,
  });

  @override
  State<QrUploadWidget> createState() => _QrUploadWidgetState();
}

class _QrUploadWidgetState extends State<QrUploadWidget> {
  final ImagePicker _picker = ImagePicker();
  XFile? _selectedFile;
  Uint8List? _previewBytes;

  Future<void> _seleccionarImagen(ImageSource source) async {
    try {
      final file = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 90,
      );

      if (file != null) {
        final bytes = await file.readAsBytes();
        setState(() {
          _selectedFile = file;
          _previewBytes = bytes;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al seleccionar imagen: $e')),
        );
      }
    }
  }

  void _limpiarSeleccion() {
    setState(() {
      _selectedFile = null;
      _previewBytes = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedFile != null && _previewBytes != null) {
      return Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Text(
                'Vista previa del nuevo código QR',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Image.memory(
                    _previewBytes!,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _selectedFile!.name,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: widget.isSubiendo ? null : _limpiarSeleccion,
                      child: const Text('Cambiar imagen'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange.shade800,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: widget.isSubiendo
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.cloud_upload),
                      label: Text(widget.isSubiendo
                          ? 'Subiendo...'
                          : 'Confirmar y Activar'),
                      onPressed: widget.isSubiendo
                          ? null
                          : () {
                              if (_selectedFile != null) {
                                widget.onSubir(_selectedFile!);
                              }
                            },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade300, style: BorderStyle.solid),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.qr_code_scanner,
                size: 48,
                color: Colors.orange.shade800,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Cargar Código QR de la Sucursal',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Subí la imagen del código QR oficial de cobro (MercadoPago, Banco, Simple, etc.). Formatos: PNG, JPG, WEBP (máx. 5MB).',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade800,
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Elegir de Galería'),
                  onPressed: widget.isSubiendo
                      ? null
                      : () => _seleccionarImagen(ImageSource.gallery),
                ),
                if (!kIsWeb) ...[
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orange.shade900,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Cámara'),
                    onPressed: widget.isSubiendo
                        ? null
                        : () => _seleccionarImagen(ImageSource.camera),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
