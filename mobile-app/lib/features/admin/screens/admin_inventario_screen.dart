import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/admin_provider.dart';

class AdminInventarioScreen extends StatefulWidget {
  const AdminInventarioScreen({super.key});

  @override
  State<AdminInventarioScreen> createState() => _AdminInventarioScreenState();
}

class _AdminInventarioScreenState extends State<AdminInventarioScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AdminProvider>().cargarInventario();
    });
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
    final items = admin.inventarioFiltrado;

    final filtros = [
      {'label': 'Todos', 'key': 'todos'},
      {'label': 'Disponibles', 'key': 'disponibles'},
      {'label': 'Stock bajo', 'key': 'stock bajo'},
      {'label': 'Agotados', 'key': 'agotados'},
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventario Global',
            style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.blueGrey.shade800,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.go('/admin'),
        ),
      ),
      body: admin.isLoading && admin.inventario.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : admin.errorMessage != null && admin.inventario.isEmpty
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
                          onPressed: () => admin.cargarInventario(),
                          child: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => admin.cargarInventario(),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 850),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Chips de filtros
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                            child: Row(
                              children: filtros.map((f) {
                                final isSelected =
                                    admin.filtroInventario.toLowerCase() ==
                                        f['key'];
                                return Padding(
                                  padding: const EdgeInsets.only(right: 8.0),
                                  child: ChoiceChip(
                                    label: Text(f['label']!),
                                    selected: isSelected,
                                    onSelected: (selected) {
                                      if (selected) {
                                        admin.setFiltroInventario(f['key']!);
                                      }
                                    },
                                  ),
                                );
                              }).toList(),
                            ),
                          ),

                          // Contador
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 4),
                            child: Text(
                              '${items.length} registros',
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
                            child: items.isEmpty
                                ? const Center(
                                    child: Text(
                                      'No hay registros para este filtro',
                                      style: TextStyle(fontSize: 16),
                                    ),
                                  )
                                : ListView.builder(
                                    padding: const EdgeInsets.all(12),
                                    itemCount: items.length,
                                    itemBuilder: (context, index) {
                                      final item = items[index];
                                      final nombreProducto =
                                          item['nombre_producto']?.toString() ??
                                              'Producto';
                                      final nombreSucursal =
                                          item['nombre_sucursal']?.toString() ??
                                              'Sucursal';
                                      final nombreTalla =
                                          item['nombre_talla']?.toString() ??
                                              '-';
                                      final nombreColor =
                                          item['nombre_color']?.toString() ??
                                              '-';
                                      final cantDisponible =
                                          item['cantidad_disponible'] as int? ??
                                              0;
                                      final cantReservada =
                                          item['cantidad_reservada'] as int? ??
                                              0;
                                      final cantVendida =
                                          item['cantidad_vendida'] as int? ?? 0;
                                      final estado =
                                          item['estado']?.toString() ??
                                              'agotado';

                                      return Card(
                                        elevation: 1,
                                        margin:
                                            const EdgeInsets.only(bottom: 10),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.all(14.0),
                                          child: Row(
                                            children: [
                                              // Cantidad grande
                                              Container(
                                                width: 56,
                                                height: 56,
                                                decoration: BoxDecoration(
                                                  color: cantDisponible > 0
                                                      ? Colors
                                                          .blueGrey.shade50
                                                      : Colors.red.shade50,
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                ),
                                                child: Center(
                                                  child: Text(
                                                    cantDisponible.toString(),
                                                    style: TextStyle(
                                                      fontSize: 22,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: cantDisponible > 0
                                                          ? Colors.blueGrey
                                                              .shade800
                                                          : Colors.red.shade700,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 14),

                                              // Info
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      nombreProducto,
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 15,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 3),
                                                    Text(
                                                      '$nombreSucursal  •  Talla: $nombreTalla  •  Color: $nombreColor',
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color: Colors
                                                            .grey.shade700,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      'Reservado: $cantReservada  |  Vendido: $cantVendida',
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.w500,
                                                        color: Colors
                                                            .blueGrey.shade600,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              _buildStatusBadge(estado),
                                            ],
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
