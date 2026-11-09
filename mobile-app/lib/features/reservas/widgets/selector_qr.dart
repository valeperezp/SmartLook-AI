import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Imagen elegida por el cliente como su QR bancario.
class QrElegido {
  const QrElegido(this.bytes, this.nombre);

  final Uint8List bytes;
  final String nombre;
}

/// Cómo se elige el QR (se puede cambiar en las pruebas, que no abren la cámara ni la galería).
typedef SelectorQr = Future<QrElegido?> Function(BuildContext context);

/// Pregunta si usar la cámara o la galería y devuelve la imagen elegida, o null si el cliente cancela. La imagen se reduce
/// (máx. 1600 px, calidad 85) para que pese poco al guardarla en el celular y enviarla.
Future<QrElegido?> elegirQrConImagePicker(BuildContext context) async {
  final fuente = await showModalBottomSheet<ImageSource>(
    context: context,
    builder: (hoja) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Tomar una foto del QR'),
            onTap: () => Navigator.pop(hoja, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Elegir de la galería'),
            onTap: () => Navigator.pop(hoja, ImageSource.gallery),
          ),
        ],
      ),
    ),
  );
  if (fuente == null) return null;

  final foto = await ImagePicker().pickImage(source: fuente, maxWidth: 1600, maxHeight: 1600, imageQuality: 85);
  if (foto == null) return null;
  return QrElegido(await foto.readAsBytes(), foto.name);
}
