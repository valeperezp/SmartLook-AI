class VestidorPrueba {
  final String imagenResultadoUrl;
  final int productoId;
  final String productoNombre;
  final bool desdeCache;

  const VestidorPrueba({
    required this.imagenResultadoUrl,
    required this.productoId,
    required this.productoNombre,
    this.desdeCache = false,
  });

  factory VestidorPrueba.fromJson(Map<String, dynamic> json) {
    return VestidorPrueba(
      imagenResultadoUrl: json['imagen_resultado_url'] as String? ?? '',
      productoId: json['producto_id'] as int? ?? 0,
      productoNombre: json['producto_nombre'] as String? ?? '',
      desdeCache: json['desde_cache'] as bool? ?? false,
    );
  }
}
