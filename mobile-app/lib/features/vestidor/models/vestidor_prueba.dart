class VestidorPrueba {
  final String imagenResultadoUrl;
  final int productoId;
  final String productoNombre;

  const VestidorPrueba({
    required this.imagenResultadoUrl,
    required this.productoId,
    this.productoNombre = '',
  });

  factory VestidorPrueba.fromJson(Map<String, dynamic> json) {
    return VestidorPrueba(
      imagenResultadoUrl: json['imagen_resultado_url'] as String? ?? '',
      productoId: json['producto_id'] as int? ?? 0,
      productoNombre: json['producto_nombre'] as String? ?? '',
    );
  }
}
