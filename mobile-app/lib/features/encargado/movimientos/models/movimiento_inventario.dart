class MovimientoInventario {
  final int id;
  final int inventarioId;
  final String tipo; // 'entrada' | 'salida' | 'ajuste' | 'venta' | 'reserva'
  final int cantidad;
  final String? motivo;
  final int? usuarioId;
  final String? nombreUsuario;
  final String? nombreProducto;
  final String? nombreSucursal;
  final DateTime creadoEn;

  const MovimientoInventario({
    required this.id,
    required this.inventarioId,
    required this.tipo,
    required this.cantidad,
    this.motivo,
    this.usuarioId,
    this.nombreUsuario,
    this.nombreProducto,
    this.nombreSucursal,
    required this.creadoEn,
  });

  factory MovimientoInventario.fromJson(Map<String, dynamic> json) {
    DateTime fecha;
    try {
      fecha = json['creado_en'] != null
          ? DateTime.parse(json['creado_en'].toString())
          : DateTime.now();
    } catch (_) {
      fecha = DateTime.now();
    }

    return MovimientoInventario(
      id: (json['id'] as num?)?.toInt() ?? 0,
      inventarioId: (json['inventario_id'] as num?)?.toInt() ?? 0,
      tipo: json['tipo'] as String? ?? 'ajuste',
      cantidad: (json['cantidad'] as num?)?.toInt() ?? 0,
      motivo: json['motivo'] as String?,
      usuarioId: (json['usuario_id'] as num?)?.toInt(),
      nombreUsuario: json['nombre_usuario'] as String?,
      nombreProducto: json['nombre_producto'] as String?,
      nombreSucursal: json['nombre_sucursal'] as String?,
      creadoEn: fecha,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'inventario_id': inventarioId,
        'tipo': tipo,
        'cantidad': cantidad,
        'motivo': motivo,
        'usuario_id': usuarioId,
        'nombre_usuario': nombreUsuario,
        'nombre_producto': nombreProducto,
        'nombre_sucursal': nombreSucursal,
        'creado_en': creadoEn.toIso8601String(),
      };
}
