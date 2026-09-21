import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/estado_badge.dart';
import '../../../core/widgets/kpi_card.dart';
import '../../../core/widgets/loading_state.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/encargado_provider.dart';

class EncargadoDashboardScreen extends StatefulWidget {
  const EncargadoDashboardScreen({super.key});

  @override
  State<EncargadoDashboardScreen> createState() => _EncargadoDashboardScreenState();
}

class _EncargadoDashboardScreenState extends State<EncargadoDashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<EncargadoProvider>().cargarDashboard();
    });
  }

  Widget _buildMovimientoItem(Map<String, dynamic> mov) {
    final tipo = (mov['tipo']?.toString() ?? 'movimiento').toUpperCase();
    final producto = mov['nombre_producto']?.toString() ?? 'Producto';
    final cantidad = mov['cantidad'] as int? ?? 0;
    final fechaRaw = mov['creado_en']?.toString() ?? '';
    
    DateTime? fecha;
    if (fechaRaw.isNotEmpty) {
      fecha = DateTime.tryParse(fechaRaw)?.toLocal();
    }
    final fechaStr = fecha != null
        ? '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year} ${fecha.hour.toString().padLeft(2, '0')}:${fecha.minute.toString().padLeft(2, '0')}'
        : fechaRaw;

    Color badgeColor;
    Color badgeTextColor;
    IconData badgeIcon;

    if (tipo == 'ENTRADA') {
      badgeColor = Colors.green.shade50;
      badgeTextColor = Colors.green.shade800;
      badgeIcon = Icons.arrow_downward;
    } else if (tipo == 'SALIDA') {
      badgeColor = Colors.red.shade50;
      badgeTextColor = Colors.red.shade800;
      badgeIcon = Icons.arrow_upward;
    } else {
      // AJUSTE
      badgeColor = Colors.blue.shade50;
      badgeTextColor = Colors.blue.shade800;
      badgeIcon = Icons.tune;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: badgeColor,
          child: Icon(badgeIcon, color: badgeTextColor, size: 20),
        ),
        title: Text(
          producto,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        subtitle: Text(
          fechaStr,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: badgeColor,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                tipo,
                style: TextStyle(
                  color: badgeTextColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              cantidad > 0 ? '+$cantidad un.' : '$cantidad un.',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: cantidad >= 0 ? Colors.green.shade800 : Colors.red.shade800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final encargado = context.watch<EncargadoProvider>();
    final resumen = encargado.resumen;

    final nombreUsuario = auth.usuario?.nombre ?? 'Encargado';
    final nombreSucursal = auth.usuario?.sucursalNombre ?? 'Sucursal Centro';

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.store, color: Colors.white),
            SizedBox(width: 8),
            Text(
              'Panel Encargado',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ],
        ),
        backgroundColor: Colors.orange.shade800,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            tooltip: 'Cerrar sesión',
            onPressed: () => auth.logout(),
          ),
        ],
      ),
      body: encargado.isLoading && resumen == null
          ? const LoadingState(mensaje: 'Cargando panel de sucursal...')
          : encargado.errorMessage != null && resumen == null
              ? EmptyState(
                  icono: Icons.error_outline,
                  titulo: 'Error al cargar',
                  mensaje: encargado.errorMessage,
                  onReintentar: () => encargado.cargarDashboard(),
                )
              : RefreshIndicator(
                  onRefresh: () => encargado.cargarDashboard(),
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16.0),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 850),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Encabezado: Saludo y Chip de Sucursal
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
                                        'Control operativo y gestión de stock',
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
                                  avatar: const Icon(Icons.location_on, size: 16, color: Colors.deepOrange),
                                  label: Text(nombreSucursal),
                                  backgroundColor: Colors.orange.shade50,
                                  labelStyle: TextStyle(
                                    color: Colors.orange.shade900,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),

                            // Grid de 4 KPIs (2 columnas)
                            GridView.count(
                              crossAxisCount: 2,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              childAspectRatio: 1.35,
                              children: [
                                KpiCard(
                                  label: 'Unidades disponibles',
                                  valor: resumen?['total_disponibles']?.toString() ?? '0',
                                  icono: Icons.inventory,
                                  color: Colors.blue.shade700,
                                ),
                                KpiCard(
                                  label: 'Unidades reservadas',
                                  valor: resumen?['total_reservados']?.toString() ?? '0',
                                  subtitle: '${encargado.totalPendientes} pendientes',
                                  icono: Icons.bookmark,
                                  color: Colors.orange.shade800,
                                ),
                                KpiCard(
                                  label: 'Alertas de stock bajo',
                                  valor: resumen?['productos_stock_bajo']?.toString() ?? '0',
                                  icono: Icons.warning,
                                  color: Colors.amber.shade800,
                                ),
                                KpiCard(
                                  label: 'Artículos agotados',
                                  valor: resumen?['productos_agotados']?.toString() ?? '0',
                                  icono: Icons.error,
                                  color: Colors.red.shade700,
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
                                      backgroundColor: Colors.orange.shade700,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    icon: const Icon(Icons.inventory_2),
                                    label: const Text('Inventario'),
                                    onPressed: () => context.go('/encargado/inventario'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      backgroundColor: Colors.teal.shade600,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    icon: const Icon(Icons.swap_horiz),
                                    label: const Text('Movimientos'),
                                    onPressed: () => context.go('/encargado/movimientos'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      backgroundColor: Colors.deepPurple.shade600,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    icon: const Icon(Icons.calendar_today),
                                    label: const Text('Reservas'),
                                    onPressed: () => context.go('/encargado/reservas'),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      backgroundColor: Colors.indigo.shade600,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    icon: const Icon(Icons.point_of_sale),
                                    label: const Text('Ventas'),
                                    onPressed: () => context.go('/encargado/ventas'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      backgroundColor: Colors.amber.shade800,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    icon: const Icon(Icons.qr_code_scanner),
                                    label: const Text('Pagos QR'),
                                    onPressed: () => context.go('/encargado/pagos-pendientes'),
                                  ),
                                ),
                                const SizedBox(width: 10),
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
                                    icon: const Icon(Icons.qr_code_2),
                                    label: const Text('Mi QR'),
                                    onPressed: () => context.go('/encargado/mi-qr'),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 28),

                            // Sección: Alertas de reposición
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Alertas de reposición',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (encargado.alertas.isNotEmpty)
                                  Text(
                                    '${encargado.alertas.length} alertas',
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 13,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            if (encargado.alertas.isEmpty)
                              Card(
                                elevation: 1,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(20.0),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.check_circle, color: Colors.green, size: 36),
                                      const SizedBox(width: 14),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
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
                              ...encargado.alertas.take(5).map((alerta) {
                                final cantDisp = alerta['cantidad_disponible'] as num? ?? 0;
                                final stockMin = alerta['stock_minimo'] as num? ?? 0;
                                final isAgotado = cantDisp == 0;
                                final nombreProd = alerta['nombre_producto']?.toString() ?? 'Producto';
                                final talla = alerta['nombre_talla']?.toString() ?? '-';
                                final color = alerta['nombre_color']?.toString() ?? '-';

                                return Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  elevation: 1,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    side: BorderSide(
                                      color: isAgotado ? Colors.red.shade200 : Colors.amber.shade300,
                                    ),
                                  ),
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: isAgotado ? Colors.red.shade50 : Colors.amber.shade50,
                                      child: Icon(
                                        isAgotado ? Icons.error_outline : Icons.warning_amber_rounded,
                                        color: isAgotado ? Colors.red.shade700 : Colors.amber.shade800,
                                      ),
                                    ),
                                    title: Text(
                                      nombreProd,
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                    subtitle: Text(
                                      'Talla: $talla • Color: $color (Mínimo: $stockMin un.)',
                                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                                    ),
                                    trailing: EstadoBadge(
                                      estado: isAgotado ? 'agotado' : 'bajo',
                                      label: isAgotado ? 'Agotado' : '$cantDisp un.',
                                    ),
                                  ),
                                );
                              }),

                            const SizedBox(height: 28),

                            // Sección: Últimos movimientos
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Últimos movimientos',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (encargado.movimientos.isNotEmpty)
                                  Text(
                                    '${encargado.movimientos.length} en total',
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 13,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            if (encargado.movimientos.isEmpty)
                              Card(
                                elevation: 1,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                child: Padding(
                                  padding: const EdgeInsets.all(20.0),
                                  child: Row(
                                    children: [
                                      Icon(Icons.info_outline, color: Colors.grey.shade500, size: 30),
                                      const SizedBox(width: 14),
                                      Text(
                                        'No hay movimientos registrados en la sucursal.',
                                        style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            else
                              ...encargado.movimientos.take(5).map((m) => _buildMovimientoItem(m as Map<String, dynamic>)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
    );
  }
}
