import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../../core/models/disponibilidad.dart';
import '../../../../core/models/producto.dart';
import '../../../../core/models/venta.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/loading_state.dart';
import '../../../auth/providers/auth_provider.dart';
import '../providers/pos_provider.dart';
import '../widgets/carrito_pos_widget.dart';
import '../widgets/producto_busqueda_tile.dart';

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
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
    context.read<PosProvider>().cargarCatalogo(sucursalId: sucursalId);
  }

  void _abrirSelectorVariante(BuildContext context, Producto producto) async {
    final provider = context.read<PosProvider>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return FutureBuilder<ProductoDisponibilidad>(
          future: provider.consultarDisponibilidad(producto.id),
          builder: (context, snapshot) {
            final auth = context.read<AuthProvider>();
            final sucursalId = auth.usuario?.sucursalId ?? 1;

            if (snapshot.connectionState == ConnectionState.waiting) {
              return Container(
                height: 300,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: const Center(
                  child: LoadingState(mensaje: 'Verificando existencias...'),
                ),
              );
            }

            final disp = snapshot.data;
            final suc = disp?.disponibilidad.firstWhere(
              (s) => s.sucursalId == sucursalId,
              orElse: () => DisponibilidadSucursal(
                sucursalId: sucursalId,
                nombreSucursal: '',
                totalDisponible: 0,
                estado: 'agotado',
                items: [],
              ),
            );

            final variantesConStock =
                suc?.items.where((i) => i.cantidadDisponible > 0).toList() ?? [];

            return StatefulBuilder(
              builder: (ctx2, setStateModal) {
                DisponibilidadTallaColor? seleccionada =
                    variantesConStock.isNotEmpty ? variantesConStock.first : null;
                int cantidad = 1;

                return Container(
                  padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  producto.nombre,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  '\$${producto.precio.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.deepOrange,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.of(ctx).pop(),
                          ),
                        ],
                      ),
                      const Divider(height: 24),

                      if (variantesConStock.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Center(
                            child: Text(
                              'No hay stock disponible de esta prenda en esta sucursal.',
                              style: TextStyle(color: Colors.red.shade700),
                            ),
                          ),
                        )
                      else ...[
                        const Text(
                          'Seleccioná Talla y Color:',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: variantesConStock.map((v) {
                            final isSelected = seleccionada == v;
                            final label =
                                '${v.nombreTalla ?? "Única"} - ${v.nombreColor ?? "Único"} (${v.cantidadDisponible} disp.)';
                            return ChoiceChip(
                              label: Text(label),
                              selected: isSelected,
                              onSelected: (selected) {
                                if (selected) {
                                  setStateModal(() {
                                    seleccionada = v;
                                  });
                                }
                              },
                              selectedColor: Colors.blue.shade100,
                              labelStyle: TextStyle(
                                color: isSelected ? Colors.blue.shade900 : Colors.black87,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 20),

                        // Cantidad
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Cantidad a ingresar:',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                            Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline),
                                  onPressed: cantidad > 1
                                      ? () => setStateModal(() => cantidad--)
                                      : null,
                                ),
                                Text('$cantidad',
                                    style: const TextStyle(
                                        fontSize: 16, fontWeight: FontWeight.bold)),
                                IconButton(
                                  icon: const Icon(Icons.add_circle_outline),
                                  onPressed: seleccionada != null &&
                                          cantidad < seleccionada!.cantidadDisponible
                                      ? () => setStateModal(() => cantidad++)
                                      : null,
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue.shade700,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onPressed: seleccionada != null
                                ? () {
                                    provider.agregarAlCarrito(
                                      producto,
                                      variante: seleccionada,
                                      cantidad: cantidad,
                                    );
                                    Navigator.of(ctx).pop();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                            'Agregado al ticket: ${producto.nombre} x$cantidad'),
                                        duration: const Duration(seconds: 2),
                                      ),
                                    );
                                  }
                                : null,
                            child: const Text(
                              'Agregar al Ticket',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  void _abrirCarritoModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Consumer<PosProvider>(
          builder: (context, provider, child) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.75,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: CarritoPosWidget(
                items: provider.carrito,
                total: provider.total,
                unidades: provider.unidades,
                isProcesando: provider.isProcesandoVenta,
                onActualizarCantidad: provider.actualizarCantidad,
                onEliminarItem: provider.eliminarItem,
                onVaciar: () {
                  provider.vaciarCarrito();
                  Navigator.of(ctx).pop();
                },
                onCobrar: () {
                  Navigator.of(ctx).pop();
                  _mostrarSelectorCobro(context);
                },
              ),
            );
          },
        );
      },
    );
  }

  void _mostrarSelectorCobro(BuildContext context) {
    final provider = context.read<PosProvider>();
    final auth = context.read<AuthProvider>();
    final sucursalId = auth.usuario?.sucursalId ?? 1;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Seleccioná el Método de Cobro',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                'Total: \$${provider.total.toStringAsFixed(2)} (${provider.unidades} prendas)',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.deepOrange,
                ),
              ),
              const SizedBox(height: 20),

              // Opción 1: Efectivo
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.money, color: Colors.green.shade700),
                ),
                title: const Text('Efectivo (Presencial)',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Cobro en caja y entrega de comprobante físico'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  _procesarCobroDirecto(metodo: 'efectivo');
                },
              ),
              const Divider(),

              // Opción 2: Tarjeta POS
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.credit_card, color: Colors.blue.shade700),
                ),
                title: const Text('Tarjeta de Débito / Crédito',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Procesado por terminal POS físico'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  _procesarCobroDirecto(metodo: 'tarjeta');
                },
              ),
              const Divider(),

              // Opción 3: Cobro QR Dinámico
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.qr_code_2, color: Colors.orange.shade800),
                ),
                title: const Text('Cobro con QR',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Genera QR para transferencias y verificación'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  _iniciarCobroQR(sucursalId);
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  void _procesarCobroDirecto({required String metodo}) async {
    final messenger = ScaffoldMessenger.of(context);
    final provider = context.read<PosProvider>();
    final auth = context.read<AuthProvider>();
    final sucursalId = auth.usuario?.sucursalId ?? 1;

    final venta = await provider.registrarVenta(sucursalId: sucursalId);
    if (!mounted) return;

    if (venta != null) {
      _mostrarDialogoExito(context, venta, metodo: metodo);
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(provider.errorMessage ?? 'Error al procesar la venta'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  void _iniciarCobroQR(int sucursalId) async {
    final messenger = ScaffoldMessenger.of(context);
    final provider = context.read<PosProvider>();

    final venta = await provider.registrarVenta(sucursalId: sucursalId);
    if (!mounted) return;

    if (venta != null) {
      context.go('/cajero/qr?ventaId=${venta.id}&monto=${venta.total}');
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(provider.errorMessage ?? 'Error al crear la venta para QR'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  void _mostrarDialogoExito(BuildContext context, Venta venta, {required String metodo}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green.shade600, size: 28),
              const SizedBox(width: 8),
              const Text('¡Venta Exitosa!'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Ticket #${venta.id} registrado correctamente.'),
              const SizedBox(height: 8),
              Text('Método de pago: ${metodo.toUpperCase()}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('Total cobrado: \$${venta.total.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.deepOrange)),
              const SizedBox(height: 4),
              Text('${venta.totalItems} artículos (${venta.totalUnidades} prendas)'),
            ],
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade700,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Nueva Venta'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PosProvider>();
    final productos = provider.productosFiltrados;
    final categorias = provider.categorias;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Punto de Venta (POS)',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.blue.shade800,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar catálogo',
            onPressed: _recargar,
          ),
        ],
      ),
      body: provider.isLoadingProductos && productos.isEmpty
          ? const LoadingState(mensaje: 'Cargando catálogo para POS...')
          : provider.errorMessage != null && productos.isEmpty
              ? EmptyState(
                  icono: Icons.error_outline,
                  titulo: 'Error al cargar productos',
                  mensaje: provider.errorMessage,
                  onReintentar: _recargar,
                )
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 900),
                    child: Column(
                      children: [
                        // Buscador y Categorías
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            children: [
                              TextField(
                                controller: _searchController,
                                decoration: InputDecoration(
                                  hintText: 'Buscar prenda por nombre o código...',
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
                              const SizedBox(height: 8),

                              // Filtro de categorías
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(right: 6),
                                      child: ChoiceChip(
                                        label: const Text('Todas'),
                                        selected: provider.categoriaSeleccionada == null,
                                        onSelected: (_) => provider.setCategoria(null),
                                        selectedColor: Colors.blue.shade100,
                                      ),
                                    ),
                                    ...categorias.map((cat) {
                                      return Padding(
                                        padding: const EdgeInsets.only(right: 6),
                                        child: ChoiceChip(
                                          label: Text(cat.nombre),
                                          selected: provider.categoriaSeleccionada == cat.id,
                                          onSelected: (_) => provider.setCategoria(cat.id),
                                          selectedColor: Colors.blue.shade100,
                                        ),
                                      );
                                    }),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),

                        // Lista de productos
                        Expanded(
                          child: productos.isEmpty
                              ? EmptyState(
                                  icono: Icons.search_off,
                                  titulo: 'Sin resultados',
                                  mensaje: 'No se encontraron prendas con los criterios ingresados.',
                                  onReintentar: _recargar,
                                )
                              : ListView.builder(
                                  padding: const EdgeInsets.all(12),
                                  itemCount: productos.length,
                                  itemBuilder: (context, index) {
                                    final prod = productos[index];
                                    return ProductoBusquedaTile(
                                      producto: prod,
                                      onAgregar: () => _abrirSelectorVariante(context, prod),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
      // Botón flotante para ver el carrito POS con contador
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.green.shade600,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.shopping_cart),
        label: Text(
          provider.unidades > 0
              ? 'Ver Ticket (${provider.unidades}) • \$${provider.total.toStringAsFixed(2)}'
              : 'Ver Ticket',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        onPressed: () => _abrirCarritoModal(context),
      ),
    );
  }
}
