import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/estado_badge.dart';
import '../../../core/widgets/kpi_card.dart';
import '../../../core/widgets/loading_state.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/proveedor_provider.dart';

class ProveedorDashboardScreen extends StatefulWidget {
  const ProveedorDashboardScreen({super.key});

  @override
  State<ProveedorDashboardScreen> createState() => _ProveedorDashboardScreenState();
}

class _ProveedorDashboardScreenState extends State<ProveedorDashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProveedorProvider>().cargarDashboard();
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final proveedor = context.watch<ProveedorProvider>();

    final nombreUsuario = auth.usuario?.nombre ?? 'Proveedor';
    final nombreProveedor = auth.usuario?.proveedorNombre ?? 'Textiles SRL';

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.business, color: Colors.white),
            SizedBox(width: 8),
            Text(
              'Panel Proveedor',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ],
        ),
        backgroundColor: Colors.teal.shade800,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            tooltip: 'Cerrar sesión',
            onPressed: () => auth.logout(),
          ),
        ],
      ),
      body: proveedor.isLoading && proveedor.misProductos.isEmpty
          ? const LoadingState(mensaje: 'Cargando datos del proveedor...')
          : proveedor.errorMessage != null && proveedor.misProductos.isEmpty
              ? EmptyState(
                  icono: Icons.error_outline,
                  titulo: 'Error al cargar',
                  mensaje: proveedor.errorMessage,
                  onReintentar: () => proveedor.cargarDashboard(),
                )
              : RefreshIndicator(
                  onRefresh: () => proveedor.cargarDashboard(),
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16.0),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 850),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Saludo y Chip de Proveedor
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '¡Hola, $nombreUsuario!',
                                        style: const TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Gestión de catálogo y prendas suministradas',
                                        style: TextStyle(
                                          color: Colors.grey.shade600,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Chip(
                                  avatar: const Icon(Icons.factory_outlined, size: 16, color: Colors.teal),
                                  label: Text(nombreProveedor),
                                  backgroundColor: Colors.teal.shade50,
                                  labelStyle: TextStyle(
                                    color: Colors.teal.shade900,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),

                            // Grid de 4 KPIs
                            GridView.count(
                              crossAxisCount: 2,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              childAspectRatio: 1.35,
                              children: [
                                KpiCard(
                                  label: 'Total productos',
                                  valor: proveedor.totalProductos.toString(),
                                  icono: Icons.inventory_2,
                                  color: Colors.blue.shade700,
                                ),
                                KpiCard(
                                  label: 'Productos activos',
                                  valor: proveedor.totalActivos.toString(),
                                  icono: Icons.check_circle,
                                  color: Colors.green.shade700,
                                ),
                                KpiCard(
                                  label: 'Productos inactivos',
                                  valor: proveedor.totalInactivos.toString(),
                                  icono: Icons.cancel,
                                  color: Colors.grey.shade700,
                                ),
                                KpiCard(
                                  label: 'Categorías cubiertas',
                                  valor: proveedor.totalCategorias.toString(),
                                  icono: Icons.tag,
                                  color: Colors.orange.shade800,
                                ),
                              ],
                            ),
                            const SizedBox(height: 28),

                            // Accesos rápidos
                            const Text(
                              'Accesos rápidos',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      backgroundColor: Colors.teal.shade700,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    icon: const Icon(Icons.checkroom),
                                    label: const Text('Mis Productos'),
                                    onPressed: () => context.go('/proveedor/productos'),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      backgroundColor: Colors.blueGrey.shade700,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    icon: const Icon(Icons.menu_book),
                                    label: const Text('Catálogo'),
                                    onPressed: () => context.go('/proveedor/catalogo'),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 28),

                            // Sección: Últimos productos
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Últimos productos',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (proveedor.misProductos.isNotEmpty)
                                  TextButton(
                                    onPressed: () => context.go('/proveedor/productos'),
                                    child: const Text('Ver todos'),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),

                            if (proveedor.misProductos.isEmpty)
                              const EmptyState(
                                icono: Icons.inventory_2_outlined,
                                titulo: 'Aún no tenés productos cargados',
                                mensaje: 'Podés agregar prendas desde la sección Mis Productos.',
                              )
                            else
                              ...proveedor.misProductos.take(5).map((prod) {
                                final nombre = prod['nombre']?.toString() ?? 'Producto';
                                final precio = (prod['precio'] as num?)?.toDouble() ?? 0.0;
                                final activo = prod['activo'] == true;
                                final categoria = prod['categoria']?['nombre']?.toString() ?? '-';

                                return Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  elevation: 1,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: Colors.teal.shade50,
                                      child: Icon(Icons.checkroom, color: Colors.teal.shade700),
                                    ),
                                    title: Text(
                                      nombre,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                    subtitle: Text(
                                      'Categoría: $categoria',
                                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          '\$${precio.toStringAsFixed(2)}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        EstadoBadge(
                                          estado: activo ? 'activo' : 'inactivo',
                                        ),
                                      ],
                                    ),
                                    onTap: () => context.go('/proveedor/productos'),
                                  ),
                                );
                              }),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
    );
  }
}
