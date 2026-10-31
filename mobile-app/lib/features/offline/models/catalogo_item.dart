/// Una variante (producto + talla + color) del catálogo local de una sucursal, con su stock.
class CatalogoItem {
  const CatalogoItem({
    required this.inventarioId,
    required this.sucursalId,
    required this.productoId,
    this.tallaId,
    this.colorId,
    required this.nombre,
    this.nombreTalla,
    this.nombreColor,
    required this.precioCentavos,
    this.imagenUrl,
    required this.cantidadDisponible,
    required this.activo,
  });

  final int inventarioId;
  final int sucursalId;
  final int productoId;
  final int? tallaId;
  final int? colorId;
  final String nombre;
  final String? nombreTalla;
  final String? nombreColor;
  final int precioCentavos;
  final String? imagenUrl;
  final int cantidadDisponible;
  final bool activo;

  factory CatalogoItem.fromMap(Map<String, dynamic> m) {
    return CatalogoItem(
      inventarioId: m['inventario_id'] as int,
      sucursalId: m['sucursal_id'] as int,
      productoId: m['producto_id'] as int,
      tallaId: m['talla_id'] as int?,
      colorId: m['color_id'] as int?,
      nombre: m['nombre_producto'] as String,
      nombreTalla: m['nombre_talla'] as String?,
      nombreColor: m['nombre_color'] as String?,
      precioCentavos: m['precio_centavos'] as int,
      imagenUrl: m['imagen_url'] as String?,
      cantidadDisponible: m['cantidad_disponible'] as int,
      activo: (m['activo'] as int? ?? 1) == 1,
    );
  }

  bool get hayStock => cantidadDisponible > 0;

  /// "M · Blanco" (omite lo que no tenga).
  String get variante => [nombreTalla, nombreColor].whereType<String>().join(' · ');

  String get precioTexto => '\$${(precioCentavos / 100).toStringAsFixed(2)}';
}
