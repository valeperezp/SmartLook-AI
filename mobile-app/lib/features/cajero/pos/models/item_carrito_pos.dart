class ItemCarritoPos {
  final int productoId;
  final String nombreProducto;
  final double precio;
  final int? tallaId;
  final String? nombreTalla;
  final int? colorId;
  final String? nombreColor;
  int cantidad;
  final int stockMaximo;

  ItemCarritoPos({
    required this.productoId,
    required this.nombreProducto,
    required this.precio,
    this.tallaId,
    this.nombreTalla,
    this.colorId,
    this.nombreColor,
    this.cantidad = 1,
    this.stockMaximo = 999,
  });

  double get subtotal => precio * cantidad;

  Map<String, dynamic> toVentaItemJson() {
    return {
      'producto_id': productoId,
      'talla_id': tallaId,
      'color_id': colorId,
      'cantidad': cantidad,
    };
  }
}
