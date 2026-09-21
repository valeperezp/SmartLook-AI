class CarritoItem {
  final int productoId;
  final String nombreProducto;
  final double precio;
  final String? imagenUrl;
  final int? tallaId;
  final String? nombreTalla;
  final int? colorId;
  final String? nombreColor;
  final int cantidad;
  final int? maxDisponible;

  const CarritoItem({
    required this.productoId,
    required this.nombreProducto,
    required this.precio,
    this.imagenUrl,
    this.tallaId,
    this.nombreTalla,
    this.colorId,
    this.nombreColor,
    required this.cantidad,
    this.maxDisponible,
  });

  double get subtotal => precio * cantidad;

  CarritoItem copyWith({
    int? productoId,
    String? nombreProducto,
    double? precio,
    String? imagenUrl,
    int? tallaId,
    String? nombreTalla,
    int? colorId,
    String? nombreColor,
    int? cantidad,
    int? maxDisponible,
  }) {
    return CarritoItem(
      productoId: productoId ?? this.productoId,
      nombreProducto: nombreProducto ?? this.nombreProducto,
      precio: precio ?? this.precio,
      imagenUrl: imagenUrl ?? this.imagenUrl,
      tallaId: tallaId ?? this.tallaId,
      nombreTalla: nombreTalla ?? this.nombreTalla,
      colorId: colorId ?? this.colorId,
      nombreColor: nombreColor ?? this.nombreColor,
      cantidad: cantidad ?? this.cantidad,
      maxDisponible: maxDisponible ?? this.maxDisponible,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'productoId': productoId,
      'nombreProducto': nombreProducto,
      'precio': precio,
      'imagenUrl': imagenUrl,
      'tallaId': tallaId,
      'nombreTalla': nombreTalla,
      'colorId': colorId,
      'nombreColor': nombreColor,
      'cantidad': cantidad,
      'maxDisponible': maxDisponible,
    };
  }

  factory CarritoItem.fromJson(Map<String, dynamic> json) {
    return CarritoItem(
      productoId: json['productoId'] as int,
      nombreProducto: json['nombreProducto'] as String? ?? '',
      precio: (json['precio'] as num?)?.toDouble() ?? 0.0,
      imagenUrl: json['imagenUrl'] as String?,
      tallaId: json['tallaId'] as int?,
      nombreTalla: json['nombreTalla'] as String?,
      colorId: json['colorId'] as int?,
      nombreColor: json['nombreColor'] as String?,
      cantidad: json['cantidad'] as int? ?? 1,
      maxDisponible: json['maxDisponible'] as int?,
    );
  }
}
