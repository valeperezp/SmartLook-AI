import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/models/producto.dart';
import '../../../core/services/catalogo_service.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/estado_badge.dart';
import '../../../core/widgets/loading_state.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/catalogo_provider.dart';
import '../widgets/detalle_producto_modal.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  final CatalogoService _catalogoService = CatalogoService();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showDetalleModal(BuildContext context, Producto producto) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DetalleProductoModal(
        producto: producto,
        service: _catalogoService,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.checkroom, color: Colors.white),
            SizedBox(width: 8),
            Text(
              'SmartLook AI',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ],
        ),
        backgroundColor: Colors.blue.shade700,
        actions: [
          IconButton(
            icon: const Icon(Icons.receipt_long, color: Colors.white),
            tooltip: 'Mis Reservas',
            onPressed: () => context.go('/mis-reservas'),
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            tooltip: 'Cerrar sesión',
            onPressed: () => auth.logout(),
          ),
        ],
      ),
      body: Consumer<CatalogoProvider>(
        builder: (context, catalogo, child) {
          return Column(
            children: [
              // Barra de búsqueda
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Buscar prendas, estilos, colecciones...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              catalogo.setBusqueda('');
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  onChanged: (value) {
                    setState(() {});
                    catalogo.setBusqueda(value);
                  },
                ),
              ),

              // Filtros de Sucursales
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    const Icon(Icons.storefront, size: 20, color: Colors.blue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<int?>(
                            value: catalogo.sucursalSeleccionada,
                            isExpanded: true,
                            hint: const Text('Todas las sucursales'),
                            items: [
                              const DropdownMenuItem<int?>(
                                value: null,
                                child: Text('Todas las sucursales'),
                              ),
                              ...catalogo.sucursales.map(
                                (s) => DropdownMenuItem<int?>(
                                  value: s.id,
                                  child: Text('${s.nombre} (${s.ciudad ?? "Bolivia"})'),
                                ),
                              ),
                            ],
                            onChanged: (id) => catalogo.setSucursal(id),
                          ),
                        ),
                      ),
                    ),
                    if (catalogo.sucursalSeleccionada != null ||
                        catalogo.categoriaSeleccionada != null ||
                        catalogo.busqueda.isNotEmpty)
                      IconButton(
                        tooltip: 'Limpiar filtros',
                        icon: const Icon(Icons.filter_alt_off),
                        onPressed: () {
                          _searchController.clear();
                          catalogo.limpiarFiltros();
                        },
                      ),
                  ],
                ),
              ),

              // Chips de Categorías (Horizontal Scroll)
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: const Text('Todos'),
                        selected: catalogo.categoriaSeleccionada == null,
                        onSelected: (selected) {
                          if (selected) catalogo.setCategoria(null);
                        },
                      ),
                    ),
                    ...catalogo.categorias.map(
                      (cat) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(cat.nombre),
                          selected: catalogo.categoriaSeleccionada == cat.id,
                          onSelected: (selected) {
                            catalogo.setCategoria(selected ? cat.id : null);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const Divider(height: 1),

              // Contenido: Loading, Error, Empty o Grid de Productos
              Expanded(
                child: catalogo.isLoading
                    ? const LoadingState(mensaje: 'Cargando prendas...')
                    : catalogo.errorMessage != null
                        ? EmptyState(
                            icono: Icons.error_outline,
                            titulo: 'Error al cargar catálogo',
                            mensaje: catalogo.errorMessage,
                            onReintentar: () =>
                                catalogo.cargarDatosIniciales(),
                          )
                        : catalogo.productosFiltrados.isEmpty
                            ? EmptyState(
                                icono: Icons.inventory_2_outlined,
                                titulo: 'No se encontraron productos',
                                mensaje: 'Intenta cambiando los filtros o la búsqueda',
                                onReintentar: () {
                                  _searchController.clear();
                                  catalogo.limpiarFiltros();
                                },
                                textoBoton: 'Limpiar filtros',
                              )
                            : LayoutBuilder(
                                builder: (context, constraints) {
                                  final crossAxisCount = constraints.maxWidth > 900
                                      ? 4
                                      : (constraints.maxWidth > 600 ? 3 : 2);

                                  return RefreshIndicator(
                                    onRefresh: () async {
                                      await catalogo.cargarDatosIniciales();
                                    },
                                    child: GridView.builder(
                                      padding: const EdgeInsets.all(16),
                                      gridDelegate:
                                          SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: crossAxisCount,
                                        crossAxisSpacing: 14,
                                        mainAxisSpacing: 14,
                                        childAspectRatio: 0.68,
                                      ),
                                      itemCount:
                                          catalogo.productosFiltrados.length,
                                      itemBuilder: (context, index) {
                                        final producto =
                                            catalogo.productosFiltrados[index];
                                        return TweenAnimationBuilder<double>(
                                          tween: Tween(begin: 0.0, end: 1.0),
                                          duration: Duration(milliseconds: 300 + (index * 50)),
                                          builder: (ctx, value, child) => Opacity(
                                            opacity: value,
                                            child: Transform.translate(
                                              offset: Offset(0, 20 * (1 - value)),
                                              child: child,
                                            ),
                                          ),
                                          child: Card(
                                            elevation: 2,
                                            clipBehavior: Clip.antiAlias,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: InkWell(
                                              onTap: () => _showDetalleModal(
                                                  context, producto),
                                              child: Padding(
                                                padding: const EdgeInsets.all(12),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    // Contenedor visual del producto
                                                    Expanded(
                                                      child: Container(
                                                        width: double.infinity,
                                                        decoration: BoxDecoration(
                                                          color: Colors.blue.shade50,
                                                          borderRadius:
                                                              BorderRadius.circular(8),
                                                        ),
                                                        child: Center(
                                                          child: Hero(
                                                            tag: 'producto_${producto.id}',
                                                            child: Icon(
                                                              Icons.checkroom_rounded,
                                                              size: 56,
                                                              color: Colors.blue.shade400,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(height: 10),

                                                    // Badge Categoría
                                                    Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                              horizontal: 6,
                                                              vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: Colors.grey.shade200,
                                                        borderRadius:
                                                            BorderRadius.circular(4),
                                                      ),
                                                      child: Text(
                                                        producto.categoriaNombre,
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          color: Colors.grey.shade800,
                                                          fontWeight: FontWeight.w500,
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(height: 6),

                                                    // Nombre
                                                    Text(
                                                      producto.nombre,
                                                      maxLines: 2,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 14,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 6),

                                                    // Precio
                                                    Text(
                                                      'Bs. ${producto.precio.toStringAsFixed(2)}',
                                                      style: TextStyle(
                                                        color: Colors.blue.shade700,
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 15,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),

                                                    // Stock e indicador
                                                    Row(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .spaceBetween,
                                                      children: [
                                                        EstadoBadge(
                                                          estado: producto.estadoGlobal,
                                                        ),
                                                        Text(
                                                          producto.sucursalesConStock > 0
                                                              ? '${producto.sucursalesConStock} suc.'
                                                              : 'Sin stock',
                                                          style: TextStyle(
                                                            fontSize: 11,
                                                            color:
                                                                Colors.grey.shade600,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  );
                                },
                              ),
              ),
            ],
          );
        },
      ),
    );
  }
}
