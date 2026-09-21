class SucursalQR {
  final int id;
  final int sucursalId;
  final String imagenPath;
  final String imagenUrl;
  final bool activo;
  final DateTime creadoEn;
  final DateTime? desactivadoEn;

  const SucursalQR({
    required this.id,
    required this.sucursalId,
    required this.imagenPath,
    required this.imagenUrl,
    required this.activo,
    required this.creadoEn,
    this.desactivadoEn,
  });

  factory SucursalQR.fromJson(Map<String, dynamic> json) {
    DateTime creado;
    try {
      creado = DateTime.parse(json['creado_en'] as String);
    } catch (_) {
      creado = DateTime.now();
    }

    DateTime? desactivado;
    if (json['desactivado_en'] != null) {
      try {
        desactivado = DateTime.parse(json['desactivado_en'] as String);
      } catch (_) {
        desactivado = null;
      }
    }

    return SucursalQR(
      id: json['id'] as int? ?? 0,
      sucursalId: json['sucursal_id'] as int? ?? 0,
      imagenPath: json['imagen_path'] as String? ?? '',
      imagenUrl: json['imagen_url'] as String? ?? '',
      activo: json['activo'] as bool? ?? false,
      creadoEn: creado,
      desactivadoEn: desactivado,
    );
  }
}
