import 'catalogo_item.dart';

/// Una línea (variante) de una venta de contado, con cuánto se puede devolver todavía.
class ItemVentaLocal {
  const ItemVentaLocal({
    required this.productoId,
    this.tallaId,
    this.colorId,
    required this.nombre,
    required this.cantidad,
    required this.precioCentavos,
    required this.devuelta,
  });

  final int productoId;
  final int? tallaId;
  final int? colorId;
  final String nombre;
  final int cantidad;
  final int precioCentavos;

  /// Unidades ya devueltas en cambios/devoluciones anteriores.
  final int devuelta;

  int get devolvible => cantidad - devuelta;

  /// Identifica la variante dentro de la venta.
  String get clave => '$productoId|${tallaId ?? 0}|${colorId ?? 0}';

  factory ItemVentaLocal.fromMap(Map<String, dynamic> m) {
    return ItemVentaLocal(
      productoId: m['producto_id'] as int,
      tallaId: m['talla_id'] as int?,
      colorId: m['color_id'] as int?,
      nombre: m['nombre_producto'] as String,
      cantidad: m['cantidad'] as int,
      precioCentavos: m['precio_unitario_centavos'] as int,
      devuelta: m['cantidad_devuelta'] as int? ?? 0,
    );
  }
}

/// Una venta de contado guardada en el dispositivo (con o sin sus líneas cargadas).
class VentaLocal {
  const VentaLocal({
    required this.uuid,
    required this.fecha,
    required this.totalCentavos,
    required this.estado,
    this.items = const [],
  });

  final String uuid;
  final DateTime fecha;
  final int totalCentavos;
  final String estado;
  final List<ItemVentaLocal> items;

  /// Número de recibo: los primeros 8 caracteres del UUID, en mayúsculas.
  String get recibo => uuid.substring(0, uuid.length < 8 ? uuid.length : 8).toUpperCase();

  bool dentroDePlazo(int plazoDias, [DateTime? ahora]) =>
      (ahora ?? DateTime.now()).difference(fecha) <= Duration(days: plazoDias);

  factory VentaLocal.fromMap(Map<String, dynamic> m) {
    return VentaLocal(
      uuid: m['uuid'] as String,
      fecha: DateTime.parse(m['fecha'] as String).toLocal(),
      totalCentavos: m['total_centavos'] as int,
      estado: m['estado'] as String,
      items: [for (final i in (m['items'] as List? ?? const [])) ItemVentaLocal.fromMap(Map<String, dynamic>.from(i as Map))],
    );
  }
}

/// Una prenda nueva que el cliente se lleva en un cambio.
class LineaNueva {
  LineaNueva(this.producto, this.cantidad);

  final CatalogoItem producto;
  int cantidad;

  int get subtotalCentavos => producto.precioCentavos * cantidad;
}
