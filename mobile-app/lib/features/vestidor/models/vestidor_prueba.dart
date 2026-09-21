class VestidorPrueba {
  final String imagenBase64;
  final String mimeType;

  const VestidorPrueba({
    required this.imagenBase64,
    required this.mimeType,
  });

  factory VestidorPrueba.fromJson(Map<String, dynamic> json) {
    return VestidorPrueba(
      imagenBase64: json['imagen_base64'] as String? ?? '',
      mimeType: json['mime_type'] as String? ?? 'image/png',
    );
  }
}
