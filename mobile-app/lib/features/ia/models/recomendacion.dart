class Recomendacion {
  final int productoId;
  final String nombre;
  final double precio;
  final String? imagenUrl;
  final String? categoria;
  final String motivo;
  final int puntaje;
  final String? modeloArUrl;

  const Recomendacion({
    required this.productoId,
    required this.nombre,
    required this.precio,
    this.imagenUrl,
    this.categoria,
    required this.motivo,
    required this.puntaje,
    this.modeloArUrl,
  });

  factory Recomendacion.fromJson(Map<String, dynamic> json) {
    return Recomendacion(
      productoId: json['producto_id'] as int? ?? 0,
      nombre: json['nombre_producto'] as String? ?? '',
      precio: (json['precio'] as num?)?.toDouble() ?? 0.0,
      categoria: json['nombre_categoria'] as String?,
      modeloArUrl: json['modelo_ar_url'] as String?,
      imagenUrl: json['imagen_url'] as String?,
      motivo: json['motivo'] as String? ?? 'Recomendado para ti',
      puntaje: json['puntaje'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'producto_id': productoId,
        'nombre_producto': nombre,
        'precio': precio,
        'nombre_categoria': categoria,
        'modelo_ar_url': modeloArUrl,
        'imagen_url': imagenUrl,
        'motivo': motivo,
        'puntaje': puntaje,
      };
}
