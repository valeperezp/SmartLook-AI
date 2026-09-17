class DisponibilidadTallaColor {
  final int? tallaId;
  final String? nombreTalla;
  final int? colorId;
  final String? nombreColor;
  final int cantidadDisponible;

  DisponibilidadTallaColor({
    this.tallaId,
    this.nombreTalla,
    this.colorId,
    this.nombreColor,
    required this.cantidadDisponible,
  });

  factory DisponibilidadTallaColor.fromJson(Map<String, dynamic> json) {
    return DisponibilidadTallaColor(
      tallaId: json['talla_id'] as int?,
      nombreTalla: json['nombre_talla'] as String?,
      colorId: json['color_id'] as int?,
      nombreColor: json['nombre_color'] as String?,
      cantidadDisponible: json['cantidad_disponible'] as int? ?? 0,
    );
  }
}

class DisponibilidadSucursal {
  final int sucursalId;
  final String nombreSucursal;
  final String? ciudad;
  final int totalDisponible;
  final String estado; // 'disponible', 'bajo', 'agotado'
  final List<DisponibilidadTallaColor> items;

  DisponibilidadSucursal({
    required this.sucursalId,
    required this.nombreSucursal,
    this.ciudad,
    required this.totalDisponible,
    required this.estado,
    required this.items,
  });

  factory DisponibilidadSucursal.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List<dynamic>? ?? [];
    return DisponibilidadSucursal(
      sucursalId: json['sucursal_id'] as int,
      nombreSucursal: json['nombre_sucursal'] as String? ?? '',
      ciudad: json['ciudad'] as String?,
      totalDisponible: json['total_disponible'] as int? ?? 0,
      estado: json['estado'] as String? ?? 'agotado',
      items: rawItems
          .map((item) => DisponibilidadTallaColor.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}

class ProductoDisponibilidad {
  final int productoId;
  final String nombreProducto;
  final double precio;
  final int totalGlobal;
  final int sucursalesConStock;
  final List<DisponibilidadSucursal> disponibilidad;

  ProductoDisponibilidad({
    required this.productoId,
    required this.nombreProducto,
    required this.precio,
    required this.totalGlobal,
    required this.sucursalesConStock,
    required this.disponibilidad,
  });

  factory ProductoDisponibilidad.fromJson(Map<String, dynamic> json) {
    final rawDisp = json['disponibilidad'] as List<dynamic>? ?? [];
    return ProductoDisponibilidad(
      productoId: json['producto_id'] as int,
      nombreProducto: json['nombre_producto'] as String? ?? '',
      precio: (json['precio'] as num).toDouble(),
      totalGlobal: json['total_global'] as int? ?? 0,
      sucursalesConStock: json['sucursales_con_stock'] as int? ?? 0,
      disponibilidad: rawDisp
          .map((d) => DisponibilidadSucursal.fromJson(d as Map<String, dynamic>))
          .toList(),
    );
  }
}
