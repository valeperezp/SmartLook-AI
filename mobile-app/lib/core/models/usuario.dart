class Usuario {
  final int id;
  final String nombre;
  final String email;
  final String rol; // 'cliente', 'administrador', 'encargado_sucursal', 'proveedor'
  final bool activo;
  final int? sucursalId;
  final String? sucursalNombre;
  final int? proveedorId;
  final String? proveedorNombre;

  Usuario({
    required this.id,
    required this.nombre,
    required this.email,
    required this.rol,
    required this.activo,
    this.sucursalId,
    this.sucursalNombre,
    this.proveedorId,
    this.proveedorNombre,
  });

  factory Usuario.fromJson(Map<String, dynamic> json) {
    return Usuario(
      id: json['id'] as int,
      nombre: json['nombre'] as String,
      email: json['email'] as String,
      rol: json['rol'] as String,
      activo: json['activo'] as bool? ?? true,
      sucursalId: json['sucursal_id'] as int?,
      sucursalNombre: json['sucursal_nombre'] as String?,
      proveedorId: json['proveedor_id'] as int?,
      proveedorNombre: json['proveedor_nombre'] as String?,
    );
  }

  bool get isAdmin => rol == 'administrador';
  bool get isCliente => rol == 'cliente';
  bool get isEncargado => rol == 'encargado_sucursal';
  bool get isProveedor => rol == 'proveedor';
}
