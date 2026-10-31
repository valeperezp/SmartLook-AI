import 'package:flutter/foundation.dart';

import 'catalogo_local_dao.dart';

// ARCHIVO TEMPORAL DE PRUEBA — borrar cuando el catálogo se sincronice desde el backend.
//
// OJO: los ids (producto, talla, color, inventario) son inventados y NO existen en el servidor.
// Sirven para probar el catálogo del cliente y la venta del cajero en la UI, pero una operación
// enviada al backend con estos ids fallaría.

/// Prendas falsas: (producto_id, nombre, talla_id, talla, color_id, color, precio en centavos, stock).
const _prendas = <(int, String, int, String, int, String, int, int)>[
  (101, 'Camiseta básica', 2, 'M', 1, 'Blanco', 1999, 25),
  (102, 'Polo piqué', 3, 'L', 2, 'Azul marino', 2999, 14),
  (103, 'Jean slim', 4, '32', 3, 'Azul', 5999, 9),
  (104, 'Vestido floral', 1, 'S', 4, 'Rojo', 7499, 6),
  (105, 'Chaqueta de cuero', 3, 'L', 5, 'Negro', 14999, 3),
  (106, 'Sudadera con capucha', 2, 'M', 6, 'Gris', 4599, 18),
  (107, 'Falda plisada', 1, 'S', 5, 'Negro', 3999, 0),
  (108, 'Camisa de lino', 2, 'M', 7, 'Beige', 4299, 11),
  (109, 'Short deportivo', 2, 'M', 5, 'Negro', 2499, 30),
  (110, 'Abrigo de lana', 3, 'L', 6, 'Gris', 12999, 2),
];

/// Reemplaza el catálogo local por 10 prendas falsas de [sucursalId].
/// Solo en modo debug: esta carga BORRA el catálogo local y nunca debe correr en una app real.
///
/// Con [reponerAgotados] las prendas sin stock llegan con 8 unidades: sirve para probar los avisos de
/// "Avísame cuando llegue" (CU16).
Future<void> cargarCatalogoMock({int sucursalId = 1, CatalogoLocalDao? dao, bool reponerAgotados = false}) async {
  if (!kDebugMode) {
    debugPrint('[mock_data] Ignorado: los datos de prueba solo se cargan en modo debug.');
    return;
  }

  try {
    final lote = <Map<String, dynamic>>[
      for (final (i, p) in _prendas.indexed)
        {
          'inventario_id': 1001 + i,
          'sucursal_id': sucursalId,
          'producto_id': p.$1,
          'talla_id': p.$3,
          'color_id': p.$5,
          'nombre_producto': p.$2,
          'nombre_talla': p.$4,
          'nombre_color': p.$6,
          'precio_centavos': p.$7,
          'imagen_url': null,
          'cantidad_disponible': reponerAgotados && p.$8 == 0 ? 8 : p.$8,
          'activo': 1,
        },
    ];
    await (dao ?? CatalogoLocalDao()).guardarLoteCatalogo(lote);
    debugPrint('[mock_data] Catálogo de prueba cargado: ${lote.length} prendas (sucursal $sucursalId).');
  } catch (e, st) {
    debugPrint('[mock_data] No se pudo cargar el catálogo de prueba: $e\n$st');
    rethrow;
  }
}
