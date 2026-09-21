class PromocionProducto {
  final int id;
  final int productoId;
  final String nombreProducto;
  final double precioProducto;

  const PromocionProducto({
    required this.id,
    required this.productoId,
    required this.nombreProducto,
    required this.precioProducto,
  });

  factory PromocionProducto.fromJson(Map<String, dynamic> json) {
    return PromocionProducto(
      id: (json['id'] as num?)?.toInt() ?? 0,
      productoId: (json['producto_id'] as num?)?.toInt() ?? 0,
      nombreProducto: json['nombre_producto'] as String? ?? '',
      precioProducto: (json['precio_producto'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'producto_id': productoId,
        'nombre_producto': nombreProducto,
        'precio_producto': precioProducto,
      };
}

class Promocion {
  final int id;
  final String nombre;
  final String? descripcion;
  final String tipo; // 'porcentaje' | 'monto_fijo'
  final double valor;
  final String fechaInicio;
  final String fechaFin;
  final bool activo;
  final int totalProductos;
  final List<PromocionProducto> productos;

  const Promocion({
    required this.id,
    required this.nombre,
    this.descripcion,
    required this.tipo,
    required this.valor,
    required this.fechaInicio,
    required this.fechaFin,
    required this.activo,
    required this.totalProductos,
    this.productos = const [],
  });

  factory Promocion.fromJson(Map<String, dynamic> json) {
    final prodsList = json['productos'] as List<dynamic>? ?? [];
    return Promocion(
      id: (json['id'] as num?)?.toInt() ?? 0,
      nombre: json['nombre'] as String? ?? '',
      descripcion: json['descripcion'] as String?,
      tipo: json['tipo'] as String? ?? 'porcentaje',
      valor: (json['valor'] as num?)?.toDouble() ?? 0.0,
      fechaInicio: json['fecha_inicio'] as String? ?? '',
      fechaFin: json['fecha_fin'] as String? ?? '',
      activo: json['activo'] as bool? ?? true,
      totalProductos: (json['total_productos'] as num?)?.toInt() ?? 0,
      productos: prodsList
          .map((e) => PromocionProducto.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'nombre': nombre,
        'descripcion': descripcion,
        'tipo': tipo,
        'valor': valor,
        'fecha_inicio': fechaInicio,
        'fecha_fin': fechaFin,
        'activo': activo,
        'total_productos': totalProductos,
        'productos': productos.map((e) => e.toJson()).toList(),
      };
}
