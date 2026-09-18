import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/admin_provider.dart';

class AdminProductosScreen extends StatefulWidget {
  const AdminProductosScreen({super.key});

  @override
  State<AdminProductosScreen> createState() => _AdminProductosScreenState();
}

class _AdminProductosScreenState extends State<AdminProductosScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _busqueda = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AdminProvider>().cargarProductos();
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

  @override
  Widget build(BuildContext context) {
    final admin = context.watch<AdminProvider>();
    final query = _busqueda.trim().toLowerCase();

    final productosFiltrados = admin.productos.where((p) {
      if (query.isEmpty) return true;
      final nombre = (p['nombre']?.toString() ?? '').toLowerCase();
      final cat = (p['categoria']?['nombre']?.toString() ?? '').toLowerCase();
      return nombre.contains(query) || cat.contains(query);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Productos', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.teal.shade700,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.go('/admin'),
        ),
      ),
      body: admin.isLoading && admin.productos.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : admin.errorMessage != null && admin.productos.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline,
                            size: 56, color: Colors.red),
                        const SizedBox(height: 12),
                        Text(
                          admin.errorMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 16),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => admin.cargarProductos(),
                          child: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => admin.cargarProductos(),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 800),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Buscador
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                            child: TextField(
                              controller: _searchController,
                              decoration: InputDecoration(
                                hintText: 'Buscar producto o categoría...',
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
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 12),
                              ),
                              onChanged: (val) {
                                setState(() {
                                  _busqueda = val;
                                });
                              },
                            ),
                          ),

                          // Contador
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 6),
                            child: Text(
                              '${productosFiltrados.length} productos',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                          const Divider(height: 1),

                          // Lista
                          Expanded(
                            child: productosFiltrados.isEmpty
                                ? const Center(
                                    child: Text(
                                      'No se encontraron productos',
                                      style: TextStyle(fontSize: 16),
                                    ),
                                  )
                                : ListView.builder(
                                    padding: const EdgeInsets.all(12),
                                    itemCount: productosFiltrados.length,
                                    itemBuilder: (context, index) {
                                      final p = productosFiltrados[index];
                                      final nombre = p['nombre']?.toString() ??
                                          'Sin nombre';
                                      final precio =
                                          (p['precio'] as num?)?.toDouble() ??
                                              0.0;
                                      final catNombre = p['categoria']
                                              ?['nombre']
                                          ?.toString() ??
                                          'General';
                                      final totalDisp =
                                          p['total_disponible'] as int? ?? 0;
                                      final sucStock =
                                          p['sucursales_con_stock'] as int? ??
                                              0;
                                      final estado =
                                          p['estado_global']?.toString() ??
                                              'agotado';

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
                                          margin:
                                              const EdgeInsets.only(bottom: 10),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.all(12.0),
                                          child: Row(
                                            children: [
                                              Container(
                                                padding:
                                                    const EdgeInsets.all(10),
                                                decoration: BoxDecoration(
                                                  color: Colors.teal.shade50,
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: Icon(
                                                  Icons.checkroom,
                                                  size: 32,
                                                  color: Colors.teal.shade700,
                                                ),
                                              ),
                                              const SizedBox(width: 14),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      nombre,
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 15,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Row(
                                                      children: [
                                                        Container(
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                                  horizontal: 6,
                                                                  vertical: 2),
                                                          decoration:
                                                              BoxDecoration(
                                                            color: Colors
                                                                .grey.shade200,
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        4),
                                                          ),
                                                          child: Text(
                                                            catNombre,
                                                            style: TextStyle(
                                                              fontSize: 11,
                                                              color: Colors
                                                                  .grey
                                                                  .shade800,
                                                            ),
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                            width: 10),
                                                        Text(
                                                          '\$${precio.toStringAsFixed(2)}',
                                                          style: TextStyle(
                                                            fontSize: 14,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            color: Colors
                                                                .teal.shade800,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      '$totalDisp unidades en $sucStock sucursales',
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color: Colors
                                                            .grey.shade600,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              _buildStatusBadge(estado),
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
