class Sucursal {
  final int id;
  final String nombre;
  final String direccion;
  final String? ciudad;
  final String? telefono;
  final bool activa;

  Sucursal({
    required this.id,
    required this.nombre,
    required this.direccion,
    this.ciudad,
    this.telefono,
    required this.activa,
  });

  factory Sucursal.fromJson(Map<String, dynamic> json) {
    return Sucursal(
      id: json['id'] as int,
      nombre: json['nombre'] as String,
      direccion: json['direccion'] as String? ?? '',
      ciudad: json['ciudad'] as String?,
      telefono: json['telefono'] as String?,
      activa: json['activa'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'nombre': nombre,
        'direccion': direccion,
        'ciudad': ciudad,
        'telefono': telefono,
        'activa': activa,
      };
}
