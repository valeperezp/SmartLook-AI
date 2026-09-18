import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/encargado_provider.dart';
import '../widgets/modal_ajuste.dart';
import '../widgets/modal_movimiento.dart';
import '../widgets/modal_stock_minimo.dart';

class EncargadoInventarioScreen extends StatefulWidget {
  const EncargadoInventarioScreen({super.key});

  @override
  State<EncargadoInventarioScreen> createState() => _EncargadoInventarioScreenState();
}

class _EncargadoInventarioScreenState extends State<EncargadoInventarioScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _filtroEstado = 'todos';
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<EncargadoProvider>().cargarInventario();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Widget _buildStatusBadge(String estado) {
    Color textColor;
    Color bgColor;
    String label;

    switch (estado.toLowerCase()) {
      case 'disponible':
        textColor = Colors.green.shade800;
        bgColor = Colors.green.shade100;
        label = 'Disponible';
        break;
      case 'bajo':
        textColor = Colors.orange.shade900;
        bgColor = Colors.orange.shade100;
        label = 'Stock bajo';
        break;
      case 'agotado':
      default:
        textColor = Colors.red.shade800;
        bgColor = Colors.red.shade100;
        label = 'Agotado';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  List<dynamic> _filtrarItems(List<dynamic> inventario) {
    return inventario.where((item) {
      final nombre = item['nombre_producto']?.toString().toLowerCase() ?? '';
      final estado = item['estado']?.toString().toLowerCase() ?? '';
      final disponible = item['cantidad_disponible'] as int? ?? 0;

      // Filtro por texto de búsqueda
      if (_searchQuery.isNotEmpty && !nombre.contains(_searchQuery.toLowerCase())) {
        return false;
      }

      // Filtro por chip de estado
      if (_filtroEstado == 'disponibles') {
        return estado == 'disponible' || (disponible > 0 && estado != 'bajo');
      } else if (_filtroEstado == 'stock bajo') {
        return estado == 'bajo';
      } else if (_filtroEstado == 'agotados') {
        return estado == 'agotado' || disponible == 0;
      }

      return true; // 'todos'
    }).toList();
  }

  Future<void> _abrirModal(Widget modal) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: modal,
      ),
    );

    if (result == true && mounted) {
      context.read<EncargadoProvider>().cargarInventario();
    }
  }

  void _mostrarMenuGestion(BuildContext context, Map<String, dynamic> item) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final nombreProducto = item['nombre_producto']?.toString() ?? 'Producto';
        final nombreTalla = item['nombre_talla']?.toString() ?? '-';
        final nombreColor = item['nombre_color']?.toString() ?? '-';
        final cantDisponible = item['cantidad_disponible'] as int? ?? 0;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nombreProducto,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Talla: $nombreTalla  •  Color: $nombreColor  •  Disponible: $cantDisponible un.',
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.add_circle, color: Colors.green, size: 28),
                  title: const Text('Registrar entrada', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Ingreso de nueva mercancía a la sucursal'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _abrirModal(ModalMovimiento(inventarioItem: item, tipo: 'entrada'));
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.remove_circle, color: Colors.red, size: 28),
                  title: const Text('Registrar salida', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Retiro o despacho de mercancía'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _abrirModal(ModalMovimiento(inventarioItem: item, tipo: 'salida'));
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.tune, color: Colors.blue, size: 28),
                  title: const Text('Ajustar stock', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Corrección tras auditoría o conteo físico'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _abrirModal(ModalAjuste(inventarioItem: item));
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.warning_amber, color: Colors.orange, size: 28),
                  title: const Text('Stock mínimo', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Configurar umbral de alerta de reposición'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _abrirModal(ModalStockMinimo(inventarioItem: item));
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final encargado = context.watch<EncargadoProvider>();
    final itemsFiltrados = _filtrarItems(encargado.inventario);

    final filtros = [
      {'label': 'Todos', 'key': 'todos'},
      {'label': 'Disponibles', 'key': 'disponibles'},
      {'label': 'Stock bajo', 'key': 'stock bajo'},
      {'label': 'Agotados', 'key': 'agotados'},
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Mi Inventario',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.orange.shade800,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.go('/encargado'),
        ),
      ),
      body: encargado.isLoading && encargado.inventario.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : encargado.errorMessage != null && encargado.inventario.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, size: 56, color: Colors.red),
                        const SizedBox(height: 12),
                        Text(
                          encargado.errorMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 16),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => encargado.cargarInventario(),
                          child: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => encargado.cargarInventario(),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 850),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Barra de búsqueda por nombre
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                            child: TextField(
                              controller: _searchController,
                              onChanged: (val) {
                                setState(() {
                                  _searchQuery = val.trim();
                                });
                              },
                              decoration: InputDecoration(
                                hintText: 'Buscar producto por nombre...',
                                prefixIcon: const Icon(Icons.search),
                                suffixIcon: _searchQuery.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear),
                                        onPressed: () {
                                          _searchController.clear();
                                          setState(() {
                                            _searchQuery = '';
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
                          ),

                          // Chips de filtro por estado
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            child: Row(
                              children: filtros.map((f) {
                                final isSelected = _filtroEstado == f['key'];
                                return Padding(
                                  padding: const EdgeInsets.only(right: 8.0),
                                  child: ChoiceChip(
                                    label: Text(f['label']!),
                                    selected: isSelected,
                                    selectedColor: Colors.orange.shade100,
                                    labelStyle: TextStyle(
                                      color: isSelected ? Colors.orange.shade900 : Colors.black87,
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                    ),
                                    onSelected: (selected) {
                                      if (selected) {
                                        setState(() {
                                          _filtroEstado = f['key']!;
                                        });
                                      }
                                    },
                                  ),
                                );
                              }).toList(),
                            ),
                          ),

                          // Contador de registros
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: Text(
                              '${itemsFiltrados.length} registros',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                          const Divider(height: 1),

                          // Lista de inventario
                          Expanded(
                            child: itemsFiltrados.isEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.search_off, size: 48, color: Colors.grey.shade400),
                                        const SizedBox(height: 12),
                                        Text(
                                          'No se encontraron productos con estos filtros',
                                          style: TextStyle(
                                            fontSize: 15,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : ListView.builder(
                                    padding: const EdgeInsets.all(12),
                                    itemCount: itemsFiltrados.length,
                                    itemBuilder: (context, index) {
                                      final item = itemsFiltrados[index];
                                      final nombreProducto =
                                          item['nombre_producto']?.toString() ?? 'Producto';
                                      final nombreTalla = item['nombre_talla']?.toString() ?? '-';
                                      final nombreColor = item['nombre_color']?.toString() ?? '-';
                                      final cantDisponible =
                                          item['cantidad_disponible'] as int? ?? 0;
                                      final cantReservada =
                                          item['cantidad_reservada'] as int? ?? 0;
                                      final cantVendida =
                                          item['cantidad_vendida'] as int? ?? 0;
                                      final estado =
                                          item['estado']?.toString() ?? 'agotado';

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
                                          margin: const EdgeInsets.only(bottom: 10),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                        child: Padding(
                                          padding: const EdgeInsets.all(14.0),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  // Cantidad grande
                                                  Container(
                                                    width: 58,
                                                    height: 58,
                                                    decoration: BoxDecoration(
                                                      color: cantDisponible > 0
                                                          ? Colors.orange.shade50
                                                          : Colors.red.shade50,
                                                      borderRadius: BorderRadius.circular(10),
                                                    ),
                                                    child: Center(
                                                      child: Text(
                                                        cantDisponible.toString(),
                                                        style: TextStyle(
                                                          fontSize: 24,
                                                          fontWeight: FontWeight.bold,
                                                          color: cantDisponible > 0
                                                              ? Colors.orange.shade900
                                                              : Colors.red.shade700,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 14),

                                                  // Info principal
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        Text(
                                                          nombreProducto,
                                                          style: const TextStyle(
                                                            fontWeight: FontWeight.bold,
                                                            fontSize: 15,
                                                          ),
                                                        ),
                                                        const SizedBox(height: 3),
                                                        Text(
                                                          'Talla: $nombreTalla  •  Color: $nombreColor',
                                                          style: TextStyle(
                                                            fontSize: 13,
                                                            color: Colors.grey.shade700,
                                                          ),
                                                        ),
                                                        const SizedBox(height: 4),
                                                        Text(
                                                          'Reservado: $cantReservada  |  Vendido: $cantVendida',
                                                          style: TextStyle(
                                                            fontSize: 12,
                                                            fontWeight: FontWeight.w500,
                                                            color: Colors.grey.shade600,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  _buildStatusBadge(estado),
                                                ],
                                              ),
                                              const SizedBox(height: 10),
                                              const Divider(height: 1),
                                              const SizedBox(height: 8),

                                              // Botón Gestionar
                                              Align(
                                                alignment: Alignment.centerRight,
                                                child: OutlinedButton.icon(
                                                  style: OutlinedButton.styleFrom(
                                                    foregroundColor: Colors.orange.shade900,
                                                    side: BorderSide(color: Colors.orange.shade300),
                                                    padding: const EdgeInsets.symmetric(
                                                      horizontal: 14,
                                                      vertical: 8,
                                                    ),
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius: BorderRadius.circular(8),
                                                    ),
                                                  ),
                                                  icon: const Icon(Icons.tune, size: 18),
                                                  label: const Text(
                                                    'Gestionar',
                                                    style: TextStyle(fontWeight: FontWeight.bold),
                                                  ),
                                                  onPressed: () => _mostrarMenuGestion(context, item),
                                                ),
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
    );
  }
}
