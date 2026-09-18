import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/estado_badge.dart';
import '../../../core/widgets/kpi_card.dart';
import '../../../core/widgets/loading_state.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/admin_provider.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AdminProvider>().cargarDashboard();
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final admin = context.watch<AdminProvider>();
    final resumen = admin.resumen;

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.admin_panel_settings, color: Colors.white),
            SizedBox(width: 8),
            Text(
              'Panel Admin',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ],
        ),
        backgroundColor: Colors.indigo.shade800,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            tooltip: 'Cerrar sesión',
            onPressed: () => auth.logout(),
          ),
        ],
      ),
      body: admin.isLoading && resumen == null
          ? const LoadingState(mensaje: 'Cargando datos del panel...')
          : admin.errorMessage != null && resumen == null
              ? EmptyState(
                  icono: Icons.error_outline,
                  titulo: 'Error al cargar',
                  mensaje: admin.errorMessage,
                  onReintentar: () => admin.cargarDashboard(),
                )
              : RefreshIndicator(
                  onRefresh: () => admin.cargarDashboard(),
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16.0),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 900),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Bienvenida
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '¡Hola, ${auth.usuario?.nombre ?? "Admin"}!',
                                      style: const TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Resumen general del inventario y operaciones',
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                                Chip(
                                  label: const Text('Administrador'),
                                  backgroundColor: Colors.indigo.shade50,
                                  labelStyle: TextStyle(
                                    color: Colors.indigo.shade800,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),

                            // Grid de 6 KPIs
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final crossAxisCount =
                                    constraints.maxWidth > 650 ? 3 : 2;
                                return GridView.count(
                                  crossAxisCount: crossAxisCount,
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                  childAspectRatio: 1.25,
                                  children: [
                                    KpiCard(
                                      label: 'Unidades disponibles',
                                      valor: resumen?['total_disponibles']
                                              ?.toString() ??
                                          '0',
                                      icono: Icons.inventory_2,
                                      color: Colors.blue.shade700,
                                    ),
                                    KpiCard(
                                      label: 'Unidades reservadas',
                                      valor: resumen?['total_reservados']
                                              ?.toString() ??
                                          '0',
                                      icono: Icons.bookmark,
                                      color: Colors.orange.shade800,
                                    ),
                                    KpiCard(
                                      label: 'Unidades vendidas',
                                      valor: resumen?['total_vendidos']
                                              ?.toString() ??
                                          '0',
                                      icono: Icons.sell,
                                      color: Colors.green.shade700,
                                    ),
                                    KpiCard(
                                      label: 'Productos agotados',
                                      valor: resumen?['productos_agotados']
                                              ?.toString() ??
                                          '0',
                                      icono: Icons.error_outline,
                                      color: Colors.red.shade700,
                                    ),
                                    KpiCard(
                                      label: 'Stock bajo',
                                      valor: resumen?['productos_stock_bajo']
                                              ?.toString() ??
                                          '0',
                                      icono: Icons.warning_amber_rounded,
                                      color: Colors.amber.shade800,
                                    ),
                                    KpiCard(
                                      label: 'Sucursales activas',
                                      valor: resumen?['total_sucursales']
                                              ?.toString() ??
                                          '0',
                                      icono: Icons.storefront,
                                      color: Colors.purple.shade700,
                                    ),
                                  ],
                                );
                              },
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
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 14),
                                      backgroundColor: Colors.indigo.shade600,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    icon: const Icon(Icons.people),
                                    label: const Text('Usuarios'),
                                    onPressed: () =>
                                        context.go('/admin/usuarios'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 14),
                                      backgroundColor: Colors.teal.shade600,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    icon: const Icon(Icons.checkroom),
                                    label: const Text('Productos'),
                                    onPressed: () =>
                                        context.go('/admin/productos'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 14),
                                      backgroundColor: Colors.blueGrey.shade700,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    icon: const Icon(Icons.inventory),
                                    label: const Text('Inventario'),
                                    onPressed: () =>
                                        context.go('/admin/inventario'),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 28),

                            // Alertas de stock
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Alertas de stock',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (admin.alertas.isNotEmpty)
                                  Text(
                                    '${admin.alertas.length} en total',
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 13,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            if (admin.alertas.isEmpty)
                              Card(
                                elevation: 1,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(20.0),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.check_circle,
                                          color: Colors.green, size: 36),
                                      const SizedBox(width: 14),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Todo en orden',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                          Text(
                                            'No hay alertas críticas ni stock bajo en este momento.',
                                            style: TextStyle(
                                              color: Colors.grey.shade600,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            else
                              ...admin.alertas.take(5).map((alerta) {
                                final isAgotado =
                                    (alerta['cantidad_disponible'] as int? ??
                                            0) ==
                                        0;
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  elevation: 1,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    side: BorderSide(
                                      color: isAgotado
                                          ? Colors.red.shade200
                                          : Colors.amber.shade300,
                                    ),
                                  ),
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: isAgotado
                                          ? Colors.red.shade50
                                          : Colors.amber.shade50,
                                      child: Icon(
                                        isAgotado
                                            ? Icons.error_outline
                                            : Icons.warning_amber_rounded,
                                        color: isAgotado
                                            ? Colors.red.shade700
                                            : Colors.amber.shade800,
                                      ),
                                    ),
                                    title: Text(
                                      alerta['nombre_producto']?.toString() ??
                                          'Producto',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold),
                                    ),
                                    subtitle: Text(
                                      '${alerta["nombre_sucursal"] ?? ""} — ${alerta["mensaje"] ?? ""}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                    trailing: EstadoBadge(
                                      estado: isAgotado ? 'agotado' : 'bajo',
                                      label: isAgotado
                                          ? 'Agotado'
                                          : '${alerta["cantidad_disponible"]} un.',
                                    ),
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
