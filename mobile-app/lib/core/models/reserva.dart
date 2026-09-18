class ReservaItem {
  final int id;
  final int productoId;
  final int? tallaId;
  final int? colorId;
  final int cantidad;
  final String nombreProducto;
  final String? nombreTalla;
  final String? nombreColor;
  final double precioUnitario;

  ReservaItem({
    required this.id,
    required this.productoId,
    this.tallaId,
    this.colorId,
    required this.cantidad,
    required this.nombreProducto,
    this.nombreTalla,
    this.nombreColor,
    required this.precioUnitario,
  });

  factory ReservaItem.fromJson(Map<String, dynamic> json) {
    return ReservaItem(
      id: json['id'] as int,
      productoId: json['producto_id'] as int,
      tallaId: json['talla_id'] as int?,
      colorId: json['color_id'] as int?,
      cantidad: json['cantidad'] as int? ?? 1,
      nombreProducto: json['nombre_producto'] as String? ?? '',
      nombreTalla: json['nombre_talla'] as String?,
      nombreColor: json['nombre_color'] as String?,
      precioUnitario: (json['precio_unitario'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'producto_id': productoId,
        'talla_id': tallaId,
        'color_id': colorId,
        'cantidad': cantidad,
        'nombre_producto': nombreProducto,
        'nombre_talla': nombreTalla,
        'nombre_color': nombreColor,
        'precio_unitario': precioUnitario,
      };
}

class Reserva {
  final int id;
  final int clienteId;
  final int sucursalId;
  final String estado; // 'pendiente', 'confirmada', 'atendida', 'cancelada'
  final DateTime? horarioAproximado;
  final DateTime creadaEn;
  final String? nombreSucursal;
  final String? nombreCliente;
  final String? emailCliente;
  final List<ReservaItem> items;
  final int totalItems;
  final int totalUnidades;
  final double totalEstimado;

  Reserva({
    required this.id,
    required this.clienteId,
    required this.sucursalId,
    required this.estado,
    this.horarioAproximado,
    required this.creadaEn,
    this.nombreSucursal,
    this.nombreCliente,
    this.emailCliente,
    required this.items,
    required this.totalItems,
    required this.totalUnidades,
    required this.totalEstimado,
  });

  factory Reserva.fromJson(Map<String, dynamic> json) {
    final itemsJson = json['items'] as List<dynamic>? ?? [];
    return Reserva(
      id: json['id'] as int,
      clienteId: json['cliente_id'] as int,
      sucursalId: json['sucursal_id'] as int,
      estado: json['estado'] as String? ?? 'pendiente',
      horarioAproximado: json['horario_aproximado'] != null
          ? DateTime.tryParse(json['horario_aproximado'] as String)
          : null,
      creadaEn: json['creada_en'] != null
          ? (DateTime.tryParse(json['creada_en'] as String) ?? DateTime.now())
          : DateTime.now(),
      nombreSucursal: json['nombre_sucursal'] as String?,
      nombreCliente: json['nombre_cliente'] as String?,
      emailCliente: json['email_cliente'] as String?,
      items: itemsJson
          .map((i) => ReservaItem.fromJson(i as Map<String, dynamic>))
          .toList(),
      totalItems: json['total_items'] as int? ?? itemsJson.length,
      totalUnidades: json['total_unidades'] as int? ?? 0,
      totalEstimado: (json['total_estimado'] as num?)?.toDouble() ?? 0.0,
    );
  }

  bool get isPendiente => estado.toLowerCase() == 'pendiente';
  bool get isConfirmada => estado.toLowerCase() == 'confirmada';
  bool get isAtendida => estado.toLowerCase() == 'atendida';
  bool get isCancelada => estado.toLowerCase() == 'cancelada';
}

class ReservaItemCreate {
  final int productoId;
  final int? tallaId;
  final int? colorId;
  final int cantidad;

  ReservaItemCreate({
    required this.productoId,
    this.tallaId,
    this.colorId,
    this.cantidad = 1,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'producto_id': productoId,
      'cantidad': cantidad,
    };
    if (tallaId != null) map['talla_id'] = tallaId;
    if (colorId != null) map['color_id'] = colorId;
    return map;
  }
}

class ReservaCreate {
  final int sucursalId;
  final DateTime? horarioAproximado;
  final List<ReservaItemCreate> items;

  ReservaCreate({
    required this.sucursalId,
    this.horarioAproximado,
    required this.items,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'sucursal_id': sucursalId,
      'items': items.map((i) => i.toJson()).toList(),
    };
    if (horarioAproximado != null) {
      map['horario_aproximado'] = horarioAproximado!.toIso8601String();
    }
    return map;
  }
}
