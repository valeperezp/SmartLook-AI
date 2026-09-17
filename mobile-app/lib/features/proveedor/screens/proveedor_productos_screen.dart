import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/proveedor_provider.dart';
import '../widgets/modal_producto_form.dart';
import '../../../core/utils/app_notifications.dart';

class ProveedorProductosScreen extends StatefulWidget {
  const ProveedorProductosScreen({super.key});

  @override
  State<ProveedorProductosScreen> createState() => _ProveedorProductosScreenState();
}

class _ProveedorProductosScreenState extends State<ProveedorProductosScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProveedorProvider>().cargarDashboard();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Widget _buildEstadoBadge(bool activo) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: activo ? Colors.green.shade50 : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        activo ? 'Activo' : 'Inactivo',
        style: TextStyle(
          color: activo ? Colors.green.shade800 : Colors.grey.shade800,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildCategoriaBadge(String categoria) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.teal.shade50,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        categoria,
        style: TextStyle(
          color: Colors.teal.shade800,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  void _verDetalleModal(BuildContext context, Map<String, dynamic> prod) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final nombre = prod['nombre']?.toString() ?? 'Producto';
        final descripcion = prod['descripcion']?.toString() ?? 'Sin descripción';
        final precio = (prod['precio'] as num?)?.toDouble() ?? 0.0;
        final activo = prod['activo'] == true;
        final categoria = prod['categoria']?['nombre']?.toString() ?? '-';
        final temporada = prod['temporada']?['nombre']?.toString() ?? '-';
        final coleccion = prod['coleccion']?['nombre']?.toString() ?? '-';

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        nombre,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                    _buildEstadoBadge(activo),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  descripcion,
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 14),
                const Divider(),
                const SizedBox(height: 8),
                Text('Precio: \$${precio.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 6),
                Text('Categoría: $categoria', style: TextStyle(color: Colors.grey.shade800)),
                const SizedBox(height: 4),
                Text('Temporada: $temporada', style: TextStyle(color: Colors.grey.shade800)),
                const SizedBox(height: 4),
                Text('Colección: $coleccion', style: TextStyle(color: Colors.grey.shade800)),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cerrar'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _abrirModalProducto([Map<String, dynamic>? producto]) async {
    final proveedor = context.read<ProveedorProvider>();
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: ModalProductoForm(
          producto: producto,
          categorias: proveedor.categorias,
          temporadas: proveedor.temporadas,
          colecciones: proveedor.colecciones,
        ),
      ),
    );

    if (result == true && mounted) {
      // El provider ya recarga el catálogo en crear/actualizar
    }
  }

  Future<void> _mostrarConfirmarDesactivar(Map<String, dynamic> item, bool esReactivar) async {
    final nombre = item['nombre']?.toString() ?? 'Producto';
    final id = item['id'] as int;

    final confirmed = await AppNotifications.confirmar(
      context,
      titulo: esReactivar ? '¿Reactivar producto?' : '¿Desactivar producto?',
      mensaje: 'El producto \'$nombre\' será ${esReactivar ? "reactivado" : "desactivado"}.',
      textoConfirmar: esReactivar ? 'Reactivar' : 'Desactivar',
      destructivo: !esReactivar,
    );

    if (!confirmed || !mounted) return;

    final provider = context.read<ProveedorProvider>();
    final bool success = esReactivar
        ? await provider.reactivarProducto(id)
        : await provider.desactivarProducto(id);

    if (!mounted) return;

    if (success) {
      AppNotifications.success(
        context,
        esReactivar ? 'Producto reactivado' : 'Producto desactivado',
      );
    } else {
      AppNotifications.error(
        context,
        provider.errorMessage ??
            (esReactivar
                ? 'Error al reactivar producto'
                : 'Error al desactivar producto'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final proveedor = context.watch<ProveedorProvider>();
    final productos = proveedor.productosFiltrados;

    final filtros = [
      {'label': 'Todos', 'key': 'todos'},
      {'label': 'Activos', 'key': 'activos'},
      {'label': 'Inactivos', 'key': 'inactivos'},
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Mis Productos',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.teal.shade800,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.go('/proveedor'),
        ),
      ),
      body: proveedor.isLoading && proveedor.misProductos.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : proveedor.errorMessage != null && proveedor.misProductos.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, size: 56, color: Colors.red),
                        const SizedBox(height: 12),
                        Text(
                          proveedor.errorMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 16),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => proveedor.cargarMisProductos(),
                          child: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => proveedor.cargarMisProductos(),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 850),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Barra de búsqueda
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                            child: TextField(
                              controller: _searchController,
                              onChanged: (val) => proveedor.setBusqueda(val),
                              decoration: InputDecoration(
                                hintText: 'Buscar por nombre o categoría...',
                                prefixIcon: const Icon(Icons.search),
                                suffixIcon: _searchController.text.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear),
                                        onPressed: () {
                                          _searchController.clear();
                                          proveedor.setBusqueda('');
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
                          ),

                          // Chips de filtro: Todos, Activos, Inactivos
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            child: Row(
                              children: filtros.map((f) {
                                final isSelected = proveedor.filtroEstado == f['key'];
                                return Padding(
                                  padding: const EdgeInsets.only(right: 8.0),
                                  child: ChoiceChip(
                                    label: Text(f['label']!),
                                    selected: isSelected,
                                    selectedColor: Colors.teal.shade100,
                                    labelStyle: TextStyle(
                                      color: isSelected ? Colors.teal.shade900 : Colors.black87,
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                    ),
                                    onSelected: (selected) {
                                      if (selected) {
                                        proveedor.setFiltroEstado(f['key']!);
                                      }
                                    },
                                  ),
                                );
                              }).toList(),
                            ),
                          ),

                          // Contador
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: Text(
                              '${productos.length} productos',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                          const Divider(height: 1),

                          // Lista de Productos
                          Expanded(
                            child: productos.isEmpty
                                ? Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(32.0),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.checkroom_outlined, size: 52, color: Colors.grey.shade400),
                                          const SizedBox(height: 12),
                                          Text(
                                            proveedor.misProductos.isEmpty
                                                ? 'No tenés productos. Creá el primero en la siguiente fase.'
                                                : 'No se encontraron productos con estos filtros',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: 15,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                : ListView.builder(
                                    padding: const EdgeInsets.all(12),
                                    itemCount: productos.length,
                                    itemBuilder: (context, index) {
                                      final item = productos[index];
                                      final nombre = item['nombre']?.toString() ?? 'Producto';
                                      final precio = (item['precio'] as num?)?.toDouble() ?? 0.0;
                                      final activo = item['activo'] == true;
                                      final categoria = item['categoria']?['nombre']?.toString() ?? '-';
                                      final temporada = item['temporada']?['nombre']?.toString();
                                      final coleccion = item['coleccion']?['nombre']?.toString();

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
                                          elevation: 1,
                                          margin: const EdgeInsets.only(bottom: 12),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(12),
                                            side: BorderSide(
                                              color: activo ? Colors.grey.shade200 : Colors.red.shade100,
                                            ),
                                          ),
                                        child: Padding(
                                          padding: const EdgeInsets.all(14),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  // Icono de prenda
                                                  Container(
                                                    width: 48,
                                                    height: 48,
                                                    decoration: BoxDecoration(
                                                      color: Colors.teal.shade50,
                                                      borderRadius: BorderRadius.circular(10),
                                                    ),
                                                    child: Icon(
                                                      Icons.checkroom,
                                                      color: Colors.teal.shade800,
                                                      size: 26,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 12),

                                                  // Info principal
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        Text(
                                                          nombre,
                                                          style: const TextStyle(
                                                            fontWeight: FontWeight.bold,
                                                            fontSize: 15,
                                                          ),
                                                        ),
                                                        const SizedBox(height: 4),
                                                        Row(
                                                          children: [
                                                            _buildCategoriaBadge(categoria),
                                                            const SizedBox(width: 8),
                                                            Text(
                                                              '\$${precio.toStringAsFixed(2)}',
                                                              style: TextStyle(
                                                                fontWeight: FontWeight.bold,
                                                                fontSize: 14,
                                                                color: Colors.teal.shade900,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  _buildEstadoBadge(activo),
                                                ],
                                              ),

                                              // Temporada y Colección (texto pequeño)
                                              if (temporada != null || coleccion != null) ...[
                                                const SizedBox(height: 8),
                                                Text(
                                                  '${temporada != null ? "Temporada: $temporada" : ""}${temporada != null && coleccion != null ? "  •  " : ""}${coleccion != null ? "Colección: $coleccion" : ""}',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.grey.shade600,
                                                  ),
                                                ),
                                              ],

                                              const SizedBox(height: 10),
                                              const Divider(height: 1),
                                              const SizedBox(height: 8),

                                              // Botones de acción: Ver y Gestionar
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.end,
                                                children: [
                                                  OutlinedButton.icon(
                                                    style: OutlinedButton.styleFrom(
                                                      foregroundColor: Colors.blueGrey.shade800,
                                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                      shape: RoundedRectangleBorder(
                                                        borderRadius: BorderRadius.circular(8),
                                                      ),
                                                    ),
                                                    icon: const Icon(Icons.visibility_outlined, size: 16),
                                                    label: const Text('Ver'),
                                                    onPressed: () => _verDetalleModal(context, item as Map<String, dynamic>),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  PopupMenuButton<String>(
                                                    tooltip: 'Gestionar producto',
                                                    onSelected: (action) {
                                                      if (action == 'editar') {
                                                        _abrirModalProducto(item as Map<String, dynamic>);
                                                      } else if (action == 'desactivar') {
                                                        _mostrarConfirmarDesactivar(item as Map<String, dynamic>, false);
                                                      } else if (action == 'reactivar') {
                                                        _mostrarConfirmarDesactivar(item as Map<String, dynamic>, true);
                                                      }
                                                    },
                                                    itemBuilder: (context) => [
                                                      const PopupMenuItem<String>(
                                                        value: 'editar',
                                                        child: Row(
                                                          children: [
                                                            Icon(Icons.edit, size: 18, color: Colors.blueGrey),
                                                            SizedBox(width: 8),
                                                            Text('Editar'),
                                                          ],
                                                        ),
                                                      ),
                                                      if (activo)
                                                        const PopupMenuItem<String>(
                                                          value: 'desactivar',
                                                          child: Row(
                                                            children: [
                                                              Icon(Icons.block, size: 18, color: Colors.red),
                                                              SizedBox(width: 8),
                                                              Text('Desactivar', style: TextStyle(color: Colors.red)),
                                                            ],
                                                          ),
                                                        )
                                                      else
                                                        const PopupMenuItem<String>(
                                                          value: 'reactivar',
                                                          child: Row(
                                                            children: [
                                                              Icon(Icons.refresh, size: 18, color: Colors.green),
                                                              SizedBox(width: 8),
                                                              Text('Reactivar', style: TextStyle(color: Colors.green)),
                                                            ],
                                                          ),
                                                        ),
                                                    ],
                                                    child: Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                                      decoration: BoxDecoration(
                                                        color: Colors.teal.shade700,
                                                        borderRadius: BorderRadius.circular(8),
                                                      ),
                                                      child: const Row(
                                                        mainAxisSize: MainAxisSize.min,
                                                        children: [
                                                          Icon(Icons.tune, size: 16, color: Colors.white),
                                                          SizedBox(width: 6),
                                                          Text(
                                                            'Gestionar',
                                                            style: TextStyle(
                                                              color: Colors.white,
                                                              fontWeight: FontWeight.w600,
                                                              fontSize: 13,
                                                            ),
                                                          ),
                                                          SizedBox(width: 4),
                                                          Icon(Icons.arrow_drop_down, size: 18, color: Colors.white),
                                                        ],
                                                      ),
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
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
      floatingActionButton: proveedor.filtroEstado == 'inactivos'
          ? null
          : FloatingActionButton.extended(
              backgroundColor: Colors.teal.shade800,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('Nuevo producto'),
              onPressed: () => _abrirModalProducto(),
            ),
    );
  }
}
