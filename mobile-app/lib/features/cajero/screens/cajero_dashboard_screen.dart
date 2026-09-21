import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/widgets/kpi_card.dart';
import '../../auth/providers/auth_provider.dart';
import '../ventas/providers/mis_ventas_provider.dart';

class CajeroDashboardScreen extends StatefulWidget {
  const CajeroDashboardScreen({super.key});

  @override
  State<CajeroDashboardScreen> createState() => _CajeroDashboardScreenState();
}

class _CajeroDashboardScreenState extends State<CajeroDashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      final sucursalId = auth.usuario?.sucursalId ?? 1;
      final cajeroId = auth.usuario?.id;
      context.read<MisVentasProvider>().cargarVentas(sucursalId, cajeroId: cajeroId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final ventasProv = context.watch<MisVentasProvider>();

    final nombreUsuario = auth.usuario?.nombre ?? 'Cajero';
    final nombreSucursal = auth.usuario?.sucursalNombre ?? 'Sucursal Centro';

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.point_of_sale, color: Colors.white),
            SizedBox(width: 8),
            Text(
              'Panel de Caja',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ],
        ),
        backgroundColor: Colors.blue.shade800,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            tooltip: 'Cerrar sesión',
            onPressed: () => auth.logout(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          final sucursalId = auth.usuario?.sucursalId ?? 1;
          final cajeroId = auth.usuario?.id;
          await ventasProv.cargarVentas(sucursalId, cajeroId: cajeroId);
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 850),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Encabezado
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
                              'Terminal de cobro y punto de venta',
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
                        avatar: const Icon(Icons.location_on, size: 16, color: Colors.blue),
                        label: Text(nombreSucursal),
                        backgroundColor: Colors.blue.shade50,
                        labelStyle: TextStyle(
                          color: Colors.blue.shade900,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // KPIs del turno
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.4,
                    children: [
                      KpiCard(
                        label: 'Ventas de hoy',
                        valor: '${ventasProv.totalVentas}',
                        icono: Icons.receipt_long,
                        color: Colors.blue.shade700,
                      ),
                      KpiCard(
                        label: 'Total facturado',
                        valor: '\$${ventasProv.totalFacturado.toStringAsFixed(0)}',
                        icono: Icons.attach_money,
                        color: Colors.green.shade700,
                      ),
                      KpiCard(
                        label: 'Ticket promedio',
                        valor: '\$${ventasProv.ticketPromedio.toStringAsFixed(1)}',
                        icono: Icons.show_chart,
                        color: Colors.orange.shade800,
                      ),
                      KpiCard(
                        label: 'Prendas cobradas',
                        valor: '${ventasProv.totalUnidades}',
                        icono: Icons.shopping_bag,
                        color: Colors.purple.shade700,
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),

                  // Accesos principales
                  const Text(
                    'Operaciones de Caja',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Tarjeta POS Principal
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    color: Colors.blue.shade800,
                    child: InkWell(
                      onTap: () => context.go('/cajero/pos'),
                      borderRadius: BorderRadius.circular(16),
                      child: const Padding(
                        padding: EdgeInsets.all(20),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 28,
                              backgroundColor: Colors.white24,
                              child: Icon(Icons.point_of_sale, color: Colors.white, size: 30),
                            ),
                            SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'PUNTO DE VENTA (POS)',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'Armar ticket, buscar prendas y cobrar en caja',
                                    style: TextStyle(color: Colors.white70, fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 20),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 2 Botones secundarios: Historial Ventas y Cobro QR
                  Row(
                    children: [
                      Expanded(
                        child: Card(
                          elevation: 1.5,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          child: InkWell(
                            onTap: () => context.go('/cajero/mis-ventas'),
                            borderRadius: BorderRadius.circular(14),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.teal.shade50,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(Icons.history, color: Colors.teal.shade700, size: 24),
                                  ),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'Mis Ventas',
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Historial de tickets',
                                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Card(
                          elevation: 1.5,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          child: InkWell(
                            onTap: () => context.go('/cajero/qr'),
                            borderRadius: BorderRadius.circular(14),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.shade50,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(Icons.qr_code_2, color: Colors.orange.shade800, size: 24),
                                  ),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'Cobros QR',
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Verificar transferencias',
                                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
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
