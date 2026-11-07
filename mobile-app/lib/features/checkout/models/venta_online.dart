class VentaItemCreate {
  final int productoId;
  final int? tallaId;
  final int? colorId;
  final int cantidad;

  const VentaItemCreate({
    required this.productoId,
    this.tallaId,
    this.colorId,
    required this.cantidad,
  });

  Map<String, dynamic> toJson() => {
        'producto_id': productoId,
        if (tallaId != null) 'talla_id': tallaId,
        if (colorId != null) 'color_id': colorId,
        'cantidad': cantidad,
      };
}

class VentaOnlineCreate {
  final int sucursalId;
  final List<VentaItemCreate> items;

  /// CU17: puntos del cliente que se canjean como descuento (el servidor valida el saldo y el total).
  final int puntosACanjear;

  const VentaOnlineCreate({
    required this.sucursalId,
    required this.items,
    this.puntosACanjear = 0,
  });

  Map<String, dynamic> toJson() => {
        'sucursal_id': sucursalId,
        'items': items.map((i) => i.toJson()).toList(),
        if (puntosACanjear > 0) 'puntos_a_canjear': puntosACanjear,
      };
}
