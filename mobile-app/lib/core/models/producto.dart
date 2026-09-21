class Producto {
  final int id;
  final String nombre;
  final String? descripcion;
  final double precio;
  final int categoriaId;
  final String categoriaNombre;
  final int? temporadaId;
  final String? temporadaNombre;
  final int? coleccionId;
  final String? coleccionNombre;
  final int? proveedorId;
  final String? modeloArUrl;
  final String? imagenUrl;
  final bool activo;
  final int totalDisponible;
  final int sucursalesConStock;
  final String estadoGlobal; // 'disponible', 'bajo', 'agotado'

  Producto({
    required this.id,
    required this.nombre,
    this.descripcion,
    required this.precio,
    required this.categoriaId,
    required this.categoriaNombre,
    this.temporadaId,
    this.temporadaNombre,
    this.coleccionId,
    this.coleccionNombre,
    this.proveedorId,
    this.modeloArUrl,
    this.imagenUrl,
    required this.activo,
    required this.totalDisponible,
    required this.sucursalesConStock,
    required this.estadoGlobal,
  });

  factory Producto.fromJson(Map<String, dynamic> json) {
    // Extraer nombres anidados si vienen como objetos
    final categoriaObj = json['categoria'] as Map<String, dynamic>?;
    final catNombre = json['categoria_nombre'] as String? ??
        categoriaObj?['nombre'] as String? ??
        'Sin categoría';

    final temporadaObj = json['temporada'] as Map<String, dynamic>?;
    final tempNombre = json['temporada_nombre'] as String? ??
        temporadaObj?['nombre'] as String?;

    final coleccionObj = json['coleccion'] as Map<String, dynamic>?;
    final colNombre = json['coleccion_nombre'] as String? ??
        coleccionObj?['nombre'] as String?;

    return Producto(
      id: json['id'] as int,
      nombre: json['nombre'] as String,
      descripcion: json['descripcion'] as String?,
      precio: (json['precio'] as num).toDouble(),
      categoriaId: json['categoria_id'] as int? ?? categoriaObj?['id'] as int? ?? 0,
      categoriaNombre: catNombre,
      temporadaId: json['temporada_id'] as int? ?? temporadaObj?['id'] as int?,
      temporadaNombre: tempNombre,
      coleccionId: json['coleccion_id'] as int? ?? coleccionObj?['id'] as int?,
      coleccionNombre: colNombre,
      proveedorId: json['proveedor_id'] as int?,
      modeloArUrl: json['modelo_ar_url'] as String?,
      imagenUrl: json['imagen_url'] as String?,
      activo: json['activo'] as bool? ?? true,
      totalDisponible: json['total_disponible'] as int? ?? 0,
      sucursalesConStock: json['sucursales_con_stock'] as int? ?? 0,
      estadoGlobal: json['estado_global'] as String? ?? 'agotado',
    );
  }

  bool get estaDisponible => totalDisponible > 0 && estadoGlobal != 'agotado';
  bool get tieneAr => modeloArUrl != null && modeloArUrl!.isNotEmpty;
  bool get tieneImagen => imagenUrl != null && imagenUrl!.isNotEmpty;
}
