class ProductoAr {
  final int productoId;
  final String nombre;
  final double precio;
  final String? descripcion;
  final String? modeloArUrl;
  final String? imagenUrl;
  final String? categoria;

  const ProductoAr({
    required this.productoId,
    required this.nombre,
    required this.precio,
    this.descripcion,
    this.modeloArUrl,
    this.imagenUrl,
    this.categoria,
  });

  bool get tieneAr => modeloArUrl != null && modeloArUrl!.trim().isNotEmpty;

  factory ProductoAr.fromJson(Map<String, dynamic> json) {
    final catObj = json['categoria'] as Map<String, dynamic>?;
    final catNombre = json['categoria_nombre'] as String? ??
        json['nombre_categoria'] as String? ??
        catObj?['nombre'] as String?;

    return ProductoAr(
      productoId: json['id'] as int? ?? json['producto_id'] as int? ?? 0,
      nombre: json['nombre'] as String? ?? json['nombre_producto'] as String? ?? '',
      precio: (json['precio'] as num?)?.toDouble() ?? 0.0,
      descripcion: json['descripcion'] as String?,
      modeloArUrl: json['modelo_ar_url'] as String?,
      imagenUrl: json['imagen_url'] as String?,
      categoria: catNombre,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': productoId,
        'nombre': nombre,
        'precio': precio,
        'descripcion': descripcion,
        'modelo_ar_url': modeloArUrl,
        'imagen_url': imagenUrl,
        'categoria_nombre': categoria,
      };
}
