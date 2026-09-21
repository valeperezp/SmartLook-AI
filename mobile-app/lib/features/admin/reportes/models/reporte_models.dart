class ReservasPorEstado {
  final String estado;
  final int cantidad;

  const ReservasPorEstado({
    required this.estado,
    required this.cantidad,
  });

  factory ReservasPorEstado.fromJson(Map<String, dynamic> json) {
    return ReservasPorEstado(
      estado: json['estado'] as String? ?? 'desconocido',
      cantidad: (json['cantidad'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'estado': estado,
        'cantidad': cantidad,
      };
}

class ReservasPorSucursal {
  final int sucursalId;
  final String nombreSucursal;
  final int cantidadReservas;
  final int totalUnidades;

  const ReservasPorSucursal({
    required this.sucursalId,
    required this.nombreSucursal,
    required this.cantidadReservas,
    required this.totalUnidades,
  });

  factory ReservasPorSucursal.fromJson(Map<String, dynamic> json) {
    return ReservasPorSucursal(
      sucursalId: (json['sucursal_id'] as num?)?.toInt() ?? 0,
      nombreSucursal: json['nombre_sucursal'] as String? ?? '',
      cantidadReservas: (json['cantidad_reservas'] as num?)?.toInt() ?? 0,
      totalUnidades: (json['total_unidades'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'sucursal_id': sucursalId,
        'nombre_sucursal': nombreSucursal,
        'cantidad_reservas': cantidadReservas,
        'total_unidades': totalUnidades,
      };
}

class ReservasPorDia {
  final String fecha;
  final int cantidad;

  const ReservasPorDia({
    required this.fecha,
    required this.cantidad,
  });

  factory ReservasPorDia.fromJson(Map<String, dynamic> json) {
    return ReservasPorDia(
      fecha: json['fecha'] as String? ?? '',
      cantidad: (json['cantidad'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'fecha': fecha,
        'cantidad': cantidad,
      };
}

class ResumenReportes {
  final int totalReservas;
  final int totalUnidadesReservadas;
  final List<ReservasPorEstado> reservasPorEstado;
  final int inventarioDisponible;
  final int inventarioReservado;
  final int productosStockBajo;
  final int productosAgotados;

  const ResumenReportes({
    required this.totalReservas,
    required this.totalUnidadesReservadas,
    required this.reservasPorEstado,
    required this.inventarioDisponible,
    required this.inventarioReservado,
    required this.productosStockBajo,
    required this.productosAgotados,
  });

  factory ResumenReportes.fromJson(Map<String, dynamic> json) {
    final estadosList = json['reservas_por_estado'] as List<dynamic>? ?? [];
    return ResumenReportes(
      totalReservas: (json['total_reservas'] as num?)?.toInt() ?? 0,
      totalUnidadesReservadas:
          (json['total_unidades_reservadas'] as num?)?.toInt() ?? 0,
      reservasPorEstado: estadosList
          .map((e) => ReservasPorEstado.fromJson(e as Map<String, dynamic>))
          .toList(),
      inventarioDisponible:
          (json['inventario_disponible'] as num?)?.toInt() ?? 0,
      inventarioReservado: (json['inventario_reservado'] as num?)?.toInt() ?? 0,
      productosStockBajo: (json['productos_stock_bajo'] as num?)?.toInt() ?? 0,
      productosAgotados: (json['productos_agotados'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'total_reservas': totalReservas,
        'total_unidades_reservadas': totalUnidadesReservadas,
        'reservas_por_estado': reservasPorEstado.map((e) => e.toJson()).toList(),
        'inventario_disponible': inventarioDisponible,
        'inventario_reservado': inventarioReservado,
        'productos_stock_bajo': productosStockBajo,
        'productos_agotados': productosAgotados,
      };
}
