class VentaItem {
  final int id;
  final int productoId;
  final int? tallaId;
  final int? colorId;
  final int cantidad;
  final double precioUnitario;
  final String nombreProducto;
  final String? nombreTalla;
  final String? nombreColor;
  final double subtotal;

  const VentaItem({
    required this.id,
    required this.productoId,
    this.tallaId,
    this.colorId,
    required this.cantidad,
    required this.precioUnitario,
    required this.nombreProducto,
    this.nombreTalla,
    this.nombreColor,
    required this.subtotal,
  });

  factory VentaItem.fromJson(Map<String, dynamic> json) {
    return VentaItem(
      id: json['id'] as int? ?? 0,
      productoId: json['producto_id'] as int? ?? 0,
      tallaId: json['talla_id'] as int?,
      colorId: json['color_id'] as int?,
      cantidad: json['cantidad'] as int? ?? 1,
      precioUnitario: (json['precio_unitario'] as num?)?.toDouble() ?? 0.0,
      nombreProducto: json['nombre_producto'] as String? ?? '',
      nombreTalla: json['nombre_talla'] as String?,
      nombreColor: json['nombre_color'] as String?,
      subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class Venta {
  final int id;
  final int? clienteId;
  final int sucursalId;
  final int? cajeroId;
  final String canal;
  final String estado;
  final double total;
  final DateTime creadaEn;
  final String? nombreSucursal;
  final String? nombreCajero;
  final String? nombreCliente;
  final List<VentaItem> items;
  final int totalItems;
  final int totalUnidades;

  const Venta({
    required this.id,
    this.clienteId,
    required this.sucursalId,
    this.cajeroId,
    required this.canal,
    required this.estado,
    required this.total,
    required this.creadaEn,
    this.nombreSucursal,
    this.nombreCajero,
    this.nombreCliente,
    required this.items,
    required this.totalItems,
    required this.totalUnidades,
  });

  factory Venta.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    List<VentaItem> itemList = [];
    if (rawItems is List) {
      itemList = rawItems
          .map((i) => VentaItem.fromJson(i as Map<String, dynamic>))
          .toList();
    }

    DateTime fechaParsed;
    try {
      fechaParsed = DateTime.parse(json['creada_en'] as String);
    } catch (_) {
      fechaParsed = DateTime.now();
    }

    return Venta(
      id: json['id'] as int,
      clienteId: json['cliente_id'] as int?,
      sucursalId: json['sucursal_id'] as int? ?? 0,
      cajeroId: json['cajero_id'] as int?,
      canal: json['canal'] as String? ?? 'online',
      estado: json['estado'] as String? ?? 'pendiente',
      total: (json['total'] as num?)?.toDouble() ?? 0.0,
      creadaEn: fechaParsed,
      nombreSucursal: json['nombre_sucursal'] as String?,
      nombreCajero: json['nombre_cajero'] as String?,
      nombreCliente: json['nombre_cliente'] as String?,
      items: itemList,
      totalItems: json['total_items'] as int? ?? itemList.length,
      totalUnidades: json['total_unidades'] as int? ??
          itemList.fold(0, (acc, i) => acc + i.cantidad),
    );
  }
}
