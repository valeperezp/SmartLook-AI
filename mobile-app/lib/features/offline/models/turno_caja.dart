/// Un turno de caja del cajero (fila de `turnos_caja`).
class TurnoCaja {
  const TurnoCaja({
    required this.id,
    required this.cajeroId,
    required this.sucursalId,
    required this.montoInicialCentavos,
    required this.fechaApertura,
    required this.estado,
  });

  final String id;
  final int cajeroId;
  final int sucursalId;
  final int montoInicialCentavos;
  final DateTime fechaApertura;
  final String estado;

  factory TurnoCaja.fromMap(Map<String, dynamic> m) {
    return TurnoCaja(
      id: m['id'] as String,
      cajeroId: m['cajero_id'] as int,
      sucursalId: m['sucursal_id'] as int,
      montoInicialCentavos: m['monto_inicial_centavos'] as int,
      fechaApertura: DateTime.parse(m['fecha_apertura'] as String).toLocal(),
      estado: m['estado'] as String,
    );
  }
}

/// Una venta de contado del turno, para listarla en la pantalla de caja.
class VentaDelTurno {
  const VentaDelTurno({required this.uuid, required this.fecha, required this.totalCentavos, required this.sincronizada});

  final String uuid;
  final DateTime fecha;
  final int totalCentavos;

  /// `false` mientras la venta solo existe en el dispositivo.
  final bool sincronizada;

  factory VentaDelTurno.fromMap(Map<String, dynamic> m) {
    return VentaDelTurno(
      uuid: m['uuid'] as String,
      fecha: DateTime.parse(m['fecha'] as String).toLocal(),
      totalCentavos: m['total_centavos'] as int,
      sincronizada: m['estado'] == 'sincronizada',
    );
  }
}
