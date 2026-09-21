import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/models/categoria.dart';
import '../../../core/models/producto.dart';
import '../../../core/services/catalogo_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../../catalogo/widgets/detalle_producto_modal.dart';
import '../providers/proveedor_provider.dart';

class ProveedorCatalogoScreen extends StatefulWidget {
  const ProveedorCatalogoScreen({super.key});

  @override
  State<ProveedorCatalogoScreen> createState() => _ProveedorCatalogoScreenState();
}

class _ProveedorCatalogoScreenState extends State<ProveedorCatalogoScreen> {
  final CatalogoService _catalogoService = CatalogoService();
  final TextEditingController _searchController = TextEditingController();

  List<Producto> _productos = [];
  List<Categoria> _categorias = [];
  bool _isLoading = true;
  String? _errorMessage;

  String _busqueda = '';
  int? _categoriaIdSeleccionada; // null = Todos

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _cargarDatos() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final results = await Future.wait([
        _catalogoService.listarProductos(),
        _catalogoService.listarCategorias(),
      ]);

      if (mounted) {
        setState(() {
          _productos = results[0] as List<Producto>;
          _categorias = results[1] as List<Categoria>;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error al cargar el catálogo: $e';
          _isLoading = false;
        });
      }
    }
  }

  List<Producto> get _productosFiltrados {
    return _productos.where((prod) {
      if (_categoriaIdSeleccionada != null &&
          prod.categoriaId != _categoriaIdSeleccionada) {
        return false;
      }

      if (_busqueda.trim().isNotEmpty) {
        final query = _busqueda.trim().toLowerCase();
        if (!prod.nombre.toLowerCase().contains(query)) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  Widget _buildStatusBadge(String estado) {
    Color textColor;
    Color bgColor;
    String label;

    switch (estado.toLowerCase()) {
      case 'disponible':
        textColor = Colors.green.shade800;
        bgColor = Colors.green.shade50;
        label = 'Disponible';
        break;
      case 'bajo':
        textColor = Colors.orange.shade800;
        bgColor = Colors.orange.shade50;
        label = 'Stock bajo';
        break;
      case 'agotado':
      default:
        textColor = Colors.red.shade800;
        bgColor = Colors.red.shade50;
        label = 'Agotado';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  void _verDetalle(Producto prod) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DetalleProductoModal(
        producto: prod,
        service: _catalogoService,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final usuario = context.watch<AuthProvider>().usuario;
    final miProveedorId = usuario?.proveedorId;
    final misProductos = context.watch<ProveedorProvider>().misProductos;
    final misIds = misProductos.map((p) => p['id']).toSet();

    final productosFiltrados = _productosFiltrados;

    final screenWidth = MediaQuery.of(context).size.width;
    int crossAxisCount = 2;
    if (screenWidth >= 1100) {
      crossAxisCount = 4;
    } else if (screenWidth >= 720) {
      crossAxisCount = 3;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Catálogo completo',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.teal.shade800,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/proveedor');
            }
          },
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, size: 56, color: Colors.red),
                        const SizedBox(height: 12),
                        Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 15),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _cargarDatos,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _cargarDatos,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1000),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 1. Banner informativo (índigo claro, icono info)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.indigo.shade50,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.indigo.shade100),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.info_outline,
                                    size: 22,
                                    color: Colors.indigo.shade700,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Esta sección es de solo lectura. Solo podés gestionar tus propios productos desde \'Mis Productos\'.',
                                      style: TextStyle(
                                        color: Colors.indigo.shade900,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),

                            // 2. Campo de búsqueda
                            TextField(
                              controller: _searchController,
                              onChanged: (val) {
                                setState(() {
                                  _busqueda = val;
                                });
                              },
                              decoration: InputDecoration(
                                hintText: 'Buscar producto por nombre...',
                                prefixIcon: const Icon(Icons.search),
                                suffixIcon: _searchController.text.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear),
                                        onPressed: () {
                                          _searchController.clear();
                                          setState(() {
                                            _busqueda = '';
                                          });
                                        },
                                      )
                                    : null,
                                filled: true,
                                fillColor: Colors.grey.shade50,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(color: Colors.grey.shade300),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),

                            // 3. Chips horizontales de categorías
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  ChoiceChip(
                                    label: const Text('Todos'),
                                    selected: _categoriaIdSeleccionada == null,
                                    selectedColor: Colors.teal.shade100,
                                    labelStyle: TextStyle(
                                      color: _categoriaIdSeleccionada == null
                                          ? Colors.teal.shade900
                                          : Colors.black87,
                                      fontWeight: _categoriaIdSeleccionada == null
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                    onSelected: (selected) {
                                      if (selected) {
                                        setState(() {
                                          _categoriaIdSeleccionada = null;
                                        });
                                      }
                                    },
                                  ),
                                  const SizedBox(width: 8),
                                  ..._categorias.map((cat) {
                                    final isSelected =
                                        _categoriaIdSeleccionada == cat.id;
                                    return Padding(
                                      padding: const EdgeInsets.only(right: 8.0),
                                      child: ChoiceChip(
                                        label: Text(cat.nombre),
                                        selected: isSelected,
                                        selectedColor: Colors.teal.shade100,
                                        labelStyle: TextStyle(
                                          color: isSelected
                                              ? Colors.teal.shade900
                                              : Colors.black87,
                                          fontWeight: isSelected
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                        ),
                                        onSelected: (selected) {
                                          setState(() {
                                            _categoriaIdSeleccionada =
                                                selected ? cat.id : null;
                                          });
                                        },
                                      ),
                                    );
                                  }),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),

                            // 4. Contador de productos
                            Text(
                              '${productosFiltrados.length} productos',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 12),

                            // 5. Grid de tarjetas de productos
                            if (productosFiltrados.isEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 48),
                                child: Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.search_off,
                                        size: 56,
                                        color: Colors.grey.shade400,
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        'No hay productos que coincidan',
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            else
                              GridView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: crossAxisCount,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                  childAspectRatio: 0.72,
                                ),
                                itemCount: productosFiltrados.length,
                                itemBuilder: (context, index) {
                                  final prod = productosFiltrados[index];
                                  final esTuyo = (miProveedorId != null &&
                                          prod.proveedorId == miProveedorId) ||
                                      misIds.contains(prod.id);

                                  return Card(
                                    elevation: 1,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: BorderSide(
                                        color: esTuyo
                                            ? Colors.teal.shade200
                                            : Colors.grey.shade200,
                                      ),
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: InkWell(
                                      onTap: () => _verDetalle(prod),
                                      child: Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            // Icono de prenda + badge "TUYO" si aplica
                                            Stack(
                                              children: [
                                                Container(
                                                  height: 110,
                                                  width: double.infinity,
                                                  decoration: BoxDecoration(
                                                    color: Colors.teal.shade50,
                                                    borderRadius:
                                                        BorderRadius.circular(8),
                                                  ),
                                                  child: Center(
                                                    child: ClipRRect(
                                                      borderRadius:
                                                          BorderRadius.circular(8),
                                                      child: (prod.imagenUrl != null &&
                                                              prod.imagenUrl!.isNotEmpty)
                                                          ? Image.network(
                                                              prod.imagenUrl!,
                                                              width: double.infinity,
                                                              height: 110,
                                                              fit: BoxFit.cover,
                                                              loadingBuilder:
                                                                  (ctx, child, progress) =>
                                                                      progress == null
                                                                          ? child
                                                                          : const Center(
                                                                              child: CircularProgressIndicator(
                                                                                  strokeWidth: 2),
                                                                            ),
                                                              errorBuilder:
                                                                  (context,
                                                                          error,
                                                                          stackTrace) =>
                                                                      Icon(
                                                                Icons.checkroom,
                                                                size: 52,
                                                                color: Colors.teal.shade800,
                                                              ),
                                                            )
                                                          : Icon(
                                                              Icons.checkroom,
                                                              size: 52,
                                                              color: Colors.teal.shade800,
                                                            ),
                                                    ),
                                                  ),
                                                ),
                                                if (esTuyo)
                                                  Positioned(
                                                    top: 6,
                                                    right: 6,
                                                    child: Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 3,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color: Colors.green.shade600,
                                                        borderRadius:
                                                            BorderRadius.circular(6),
                                                        boxShadow: const [
                                                          BoxShadow(
                                                            color: Colors.black12,
                                                            blurRadius: 2,
                                                          ),
                                                        ],
                                                      ),
                                                      child: const Text(
                                                        'TUYO',
                                                        style: TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 10,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          letterSpacing: 0.5,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                            const SizedBox(height: 10),

                                            // Nombre del producto (bold, max 2 líneas)
                                            Expanded(
                                              child: Text(
                                                prod.nombre,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14,
                                                  height: 1.2,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 6),

                                            // Categoría badge
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 7,
                                                vertical: 2,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Colors.teal.shade50,
                                                borderRadius:
                                                    BorderRadius.circular(5),
                                              ),
                                              child: Text(
                                                prod.categoriaNombre,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: Colors.teal.shade800,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 8),

                                            // Precio formateado
                                            Text(
                                              '\$${prod.precio.toStringAsFixed(2)}',
                                              style: TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.teal.shade900,
                                              ),
                                            ),
                                            const SizedBox(height: 6),

                                            // Estado + Sucursales
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.spaceBetween,
                                              children: [
                                                _buildStatusBadge(
                                                  prod.estadoGlobal,
                                                ),
                                                Text(
                                                  '${prod.sucursalesConStock} sucursales',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.grey.shade600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
    );
  }
}
