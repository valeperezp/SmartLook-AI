import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../../core/models/venta.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/estado_badge.dart';
import '../../../../core/widgets/loading_state.dart';
import '../../../auth/providers/auth_provider.dart';
import '../providers/mis_ventas_provider.dart';
import '../widgets/venta_cajero_tile.dart';

class MisVentasScreen extends StatefulWidget {
  const MisVentasScreen({super.key});

  @override
  State<MisVentasScreen> createState() => _MisVentasScreenState();
}

class _MisVentasScreenState extends State<MisVentasScreen> {
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
    final cajeroId = auth.usuario?.id;
    context.read<MisVentasProvider>().cargarVentas(sucursalId, cajeroId: cajeroId);
  }

  void _mostrarDetalleVenta(BuildContext context, Venta venta) {
    final provider = context.read<MisVentasProvider>();
    provider.seleccionarVenta(venta);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Consumer<MisVentasProvider>(
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
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Ticket #${venta.id}',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            Text(fechaStr, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
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

                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        // Resumen de la venta
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.blue.shade100),
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
                                      color: Colors.blue.shade900,
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
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Lista de Artículos
                        const Text('Artículos Vendidos', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 10),
                        if (venta.items.isEmpty)
                          Text('No hay ítems registrados.', style: TextStyle(color: Colors.grey.shade600))
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
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(item.nombreProducto, style: const TextStyle(fontWeight: FontWeight.bold)),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${item.nombreTalla != null ? "Talla: ${item.nombreTalla} | " : ""}${item.nombreColor != null ? "Color: ${item.nombreColor} | " : ""}${item.cantidad} un. x \$${item.precioUnitario.toStringAsFixed(2)}',
                                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    '\$${item.subtotal.toStringAsFixed(2)}',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
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
                              const Text('TOTAL COBRADO:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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

                        // Pagos registrados
                        const Text('Pagos Registrados', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 10),
                        if (prov.cargandoPagos)
                          const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()))
                        else if (prov.pagosVenta.isEmpty)
                          Text(
                            'Sin registros de pago detallados.',
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
                          )
                        else
                          ...prov.pagosVenta.map((p) {
                            return ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                p.metodo.toLowerCase() == 'qr'
                                    ? Icons.qr_code
                                    : p.metodo.toLowerCase() == 'tarjeta'
                                        ? Icons.credit_card
                                        : Icons.money,
                                color: Colors.blue.shade800,
                              ),
                              title: Text('Pago #${p.id} — ${p.metodo.toUpperCase()}',
                                  style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text('Monto: \$${p.monto.toStringAsFixed(2)}'),
                              trailing: EstadoBadge(estado: p.estado),
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

  Widget _buildFilterChip(String label, bool isSelected, VoidCallback onSelected) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) => onSelected(),
        selectedColor: Colors.blue.shade100,
        checkmarkColor: Colors.blue.shade800,
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? Colors.blue.shade900 : Colors.black87,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MisVentasProvider>();
    final ventas = provider.ventasFiltradas;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Historial de Ventas',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.blue.shade800,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
            onPressed: _recargar,
          ),
        ],
      ),
      body: provider.isLoading && provider.ventas.isEmpty
          ? const LoadingState(mensaje: 'Cargando ventas...')
          : provider.errorMessage != null && provider.ventas.isEmpty
              ? EmptyState(
                  icono: Icons.error_outline,
                  titulo: 'Error al consultar ventas',
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
                                hintText: 'Buscar por #Ticket, cliente...',
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
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(color: Colors.grey.shade300),
                                ),
                              ),
                              onChanged: (val) => provider.setBusqueda(val),
                            ),
                            const SizedBox(height: 12),

                            // Filtros de Fecha
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  const Text('Fecha: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                  _buildFilterChip('Hoy', provider.filtroFecha == 'hoy',
                                      () => provider.setFiltroFecha('hoy')),
                                  _buildFilterChip('7 Días', provider.filtroFecha == 'semana',
                                      () => provider.setFiltroFecha('semana')),
                                  _buildFilterChip('Este Mes', provider.filtroFecha == 'mes',
                                      () => provider.setFiltroFecha('mes')),
                                  _buildFilterChip('Todas', provider.filtroFecha == 'todas',
                                      () => provider.setFiltroFecha('todas')),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),

                            // Filtros de Estado
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  const Text('Estado: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                  _buildFilterChip('Todas', provider.filtroEstado == 'todas',
                                      () => provider.setFiltroEstado('todas')),
                                  _buildFilterChip('Completadas', provider.filtroEstado == 'completada',
                                      () => provider.setFiltroEstado('completada')),
                                  _buildFilterChip('Pendientes', provider.filtroEstado == 'pendiente',
                                      () => provider.setFiltroEstado('pendiente')),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),

                            // KPIs
                            Row(
                              children: [
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
                                        Text('Ventas', style: TextStyle(fontSize: 12, color: Colors.blue.shade800)),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${provider.totalVentas}',
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
                                      color: Colors.green.shade50,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: Colors.green.shade200),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Facturado', style: TextStyle(fontSize: 12, color: Colors.green.shade800)),
                                        const SizedBox(height: 4),
                                        Text(
                                          '\$${provider.totalFacturado.toStringAsFixed(0)}',
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
                                      color: Colors.orange.shade50,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: Colors.orange.shade200),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Ticket Prom.', style: TextStyle(fontSize: 12, color: Colors.orange.shade800)),
                                        const SizedBox(height: 4),
                                        Text(
                                          '\$${provider.ticketPromedio.toStringAsFixed(1)}',
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
                              ],
                            ),
                            const SizedBox(height: 20),

                            // Listado de ventas
                            if (ventas.isEmpty)
                              EmptyState(
                                icono: Icons.receipt_long_outlined,
                                titulo: 'Sin ventas',
                                mensaje: 'No hay ventas para el filtro seleccionado.',
                                onReintentar: _recargar,
                              )
                            else
                              ListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: ventas.length,
                                itemBuilder: (context, index) {
                                  final v = ventas[index];
                                  return VentaCajeroTile(
                                    venta: v,
                                    onTap: () => _mostrarDetalleVenta(context, v),
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
