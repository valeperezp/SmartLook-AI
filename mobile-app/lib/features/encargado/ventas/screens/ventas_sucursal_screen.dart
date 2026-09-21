import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../../core/models/venta.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/estado_badge.dart';
import '../../../../core/widgets/loading_state.dart';
import '../../../auth/providers/auth_provider.dart';
import '../providers/ventas_sucursal_provider.dart';
import '../widgets/venta_sucursal_tile.dart';

class VentasSucursalScreen extends StatefulWidget {
  const VentasSucursalScreen({super.key});

  @override
  State<VentasSucursalScreen> createState() => _VentasSucursalScreenState();
}

class _VentasSucursalScreenState extends State<VentasSucursalScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _recargar();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _recargar() {
    final auth = context.read<AuthProvider>();
    final sucursalId = auth.usuario?.sucursalId ?? 1;
    context.read<VentasSucursalProvider>().cargarVentas(sucursalId);
  }

  void _mostrarDetalle(BuildContext context, Venta venta) {
    final provider = context.read<VentasSucursalProvider>();
    provider.seleccionarVenta(venta);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Consumer<VentasSucursalProvider>(
          builder: (context, prov, child) {
            final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
            final fechaStr = dateFormat.format(venta.creadaEn.toLocal());

            return Container(
              height: MediaQuery.of(context).size.height * 0.85,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  // Barra de agarre
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 12, bottom: 8),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  // Encabezado del Modal
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Detalle de Venta #${venta.id}',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              fechaStr,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.of(ctx).pop(),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),

                  // Contenido scrollable
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        // Resumen Info Venta
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.orange.shade100),
                          ),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Canal:', style: TextStyle(fontWeight: FontWeight.w600)),
                                  Text(
                                    venta.canal.toUpperCase(),
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.orange.shade900,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Estado:', style: TextStyle(fontWeight: FontWeight.w600)),
                                  EstadoBadge(estado: venta.estado),
                                ],
                              ),
                              if (venta.nombreCliente != null && venta.nombreCliente!.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('Cliente:', style: TextStyle(fontWeight: FontWeight.w600)),
                                    Text(venta.nombreCliente!, style: const TextStyle(fontWeight: FontWeight.w500)),
                                  ],
                                ),
                              ],
                              if (venta.nombreCajero != null && venta.nombreCajero!.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('Atendido por:', style: TextStyle(fontWeight: FontWeight.w600)),
                                    Text(venta.nombreCajero!, style: const TextStyle(fontWeight: FontWeight.w500)),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Lista de Artículos
                        const Text(
                          'Prendas y Artículos',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (venta.items.isEmpty)
                          Text(
                            'No hay ítems registrados en esta venta.',
                            style: TextStyle(color: Colors.grey.shade600),
                          )
                        else
                          ...venta.items.map((item) {
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.grey.shade200),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.nombreProducto,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${item.nombreTalla != null ? "Talla: ${item.nombreTalla} | " : ""}${item.nombreColor != null ? "Color: ${item.nombreColor} | " : ""}${item.cantidad} un. x \$${item.precioUnitario.toStringAsFixed(2)}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    '\$${item.subtotal.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),

                        const SizedBox(height: 16),
                        // Total
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'TOTAL:',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '\$${venta.total.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.deepOrange,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 20),
                        // Sección de Pagos Registrados
                        const Text(
                          'Pagos Asociados',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (prov.cargandoPagos)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.all(12),
                              child: CircularProgressIndicator(),
                            ),
                          )
                        else if (prov.pagosVenta.isEmpty)
                          Text(
                            'No se encontraron registros de pago asociados.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                              fontStyle: FontStyle.italic,
                            ),
                          )
                        else
                          ...prov.pagosVenta.map((pago) {
                            return ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                pago.metodo.toLowerCase() == 'qr'
                                    ? Icons.qr_code
                                    : Icons.credit_card,
                                color: Colors.orange.shade800,
                              ),
                              title: Text(
                                'Pago #${pago.id} — ${pago.metodo.toUpperCase()}',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text(
                                'Monto: \$${pago.monto.toStringAsFixed(2)} | Estado: ${pago.estado}',
                              ),
                              trailing: EstadoBadge(estado: pago.estado),
                            );
                          }),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFiltroChip({
    required String label,
    required bool selected,
    required VoidCallback onSelected,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onSelected(),
        selectedColor: Colors.orange.shade100,
        checkmarkColor: Colors.orange.shade800,
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          color: selected ? Colors.orange.shade900 : Colors.black87,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<VentasSucursalProvider>();
    final ventas = provider.ventasFiltradas;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Ventas de Sucursal',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.orange.shade800,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar ventas',
            onPressed: _recargar,
          ),
        ],
      ),
      body: provider.isLoading && provider.ventas.isEmpty
          ? const LoadingState(mensaje: 'Cargando ventas de sucursal...')
          : provider.errorMessage != null && provider.ventas.isEmpty
              ? EmptyState(
                  icono: Icons.error_outline,
                  titulo: 'Error al cargar ventas',
                  mensaje: provider.errorMessage,
                  onReintentar: _recargar,
                )
              : RefreshIndicator(
                  onRefresh: () async => _recargar(),
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 850),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Buscador
                            TextField(
                              controller: _searchController,
                              decoration: InputDecoration(
                                hintText: 'Buscar por #ID, cliente o cajero...',
                                prefixIcon: const Icon(Icons.search),
                                suffixIcon: _searchController.text.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear),
                                        onPressed: () {
                                          _searchController.clear();
                                          provider.setBusqueda('');
                                        },
                                      )
                                    : null,
                                filled: true,
                                fillColor: Colors.grey.shade100,
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 12),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(color: Colors.grey.shade300),
                                ),
                              ),
                              onChanged: (val) => provider.setBusqueda(val),
                            ),
                            const SizedBox(height: 12),

                            // Barra de filtros de fecha
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  const Text('Fecha: ',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                  _buildFiltroChip(
                                    label: 'Hoy',
                                    selected: provider.filtroFecha == 'hoy',
                                    onSelected: () => provider.setFiltroFecha('hoy'),
                                  ),
                                  _buildFiltroChip(
                                    label: '7 Días',
                                    selected: provider.filtroFecha == 'semana',
                                    onSelected: () => provider.setFiltroFecha('semana'),
                                  ),
                                  _buildFiltroChip(
                                    label: 'Este Mes',
                                    selected: provider.filtroFecha == 'mes',
                                    onSelected: () => provider.setFiltroFecha('mes'),
                                  ),
                                  _buildFiltroChip(
                                    label: 'Todas',
                                    selected: provider.filtroFecha == 'todas',
                                    onSelected: () => provider.setFiltroFecha('todas'),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),

                            // Barra de filtros de Canal y Estado
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  const Text('Canal: ',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                  _buildFiltroChip(
                                    label: 'Todos',
                                    selected: provider.filtroCanal == 'todos',
                                    onSelected: () => provider.setFiltroCanal('todos'),
                                  ),
                                  _buildFiltroChip(
                                    label: 'Presencial',
                                    selected: provider.filtroCanal == 'presencial',
                                    onSelected: () => provider.setFiltroCanal('presencial'),
                                  ),
                                  _buildFiltroChip(
                                    label: 'Online',
                                    selected: provider.filtroCanal == 'online',
                                    onSelected: () => provider.setFiltroCanal('online'),
                                  ),
                                  const SizedBox(width: 10),
                                  const Text('Estado: ',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                  _buildFiltroChip(
                                    label: 'Todos',
                                    selected: provider.filtroEstado == 'todos',
                                    onSelected: () => provider.setFiltroEstado('todos'),
                                  ),
                                  _buildFiltroChip(
                                    label: 'Completadas',
                                    selected: provider.filtroEstado == 'completada',
                                    onSelected: () => provider.setFiltroEstado('completada'),
                                  ),
                                  _buildFiltroChip(
                                    label: 'Pendientes',
                                    selected: provider.filtroEstado == 'pendiente',
                                    onSelected: () => provider.setFiltroEstado('pendiente'),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Mini Tarjetas de Métricas
                            Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.shade50,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: Colors.orange.shade200),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Ventas',
                                            style: TextStyle(
                                                fontSize: 12, color: Colors.orange.shade800)),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${provider.totalVentas}',
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.orange.shade900,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.green.shade50,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: Colors.green.shade200),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Facturado',
                                            style: TextStyle(
                                                fontSize: 12, color: Colors.green.shade800)),
                                        const SizedBox(height: 4),
                                        Text(
                                          '\$${provider.montoTotal.toStringAsFixed(0)}',
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.green.shade900,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade50,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: Colors.blue.shade200),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Ticket Prom.',
                                            style: TextStyle(
                                                fontSize: 12, color: Colors.blue.shade800)),
                                        const SizedBox(height: 4),
                                        Text(
                                          '\$${provider.ticketPromedio.toStringAsFixed(1)}',
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.blue.shade900,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.purple.shade50,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: Colors.purple.shade200),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Unidades',
                                            style: TextStyle(
                                                fontSize: 12, color: Colors.purple.shade800)),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${provider.unidadesVendidas}',
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.purple.shade900,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),

                            // Lista de Ventas
                            if (ventas.isEmpty)
                              EmptyState(
                                icono: Icons.point_of_sale,
                                titulo: 'Sin ventas',
                                mensaje: 'No hay ventas para los filtros seleccionados.',
                                onReintentar: _recargar,
                              )
                            else
                              ListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: ventas.length,
                                itemBuilder: (context, index) {
                                  final v = ventas[index];
                                  return VentaSucursalTile(
                                    venta: v,
                                    onTap: () => _mostrarDetalle(context, v),
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
