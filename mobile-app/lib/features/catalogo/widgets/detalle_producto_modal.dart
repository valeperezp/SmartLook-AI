import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/models/disponibilidad.dart';
import '../../../core/models/producto.dart';
import '../../../core/services/catalogo_service.dart';
import '../../carrito/models/carrito_item.dart';
import '../../carrito/providers/carrito_provider.dart';
import '../../reservas/widgets/mini_modal_reserva.dart';

class DetalleProductoModal extends StatefulWidget {
  final Producto producto;
  final CatalogoService service;

  const DetalleProductoModal({
    super.key,
    required this.producto,
    required this.service,
  });

  @override
  State<DetalleProductoModal> createState() => _DetalleProductoModalState();
}

class _DetalleProductoModalState extends State<DetalleProductoModal> {
  ProductoDisponibilidad? _disponibilidad;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _cargarDisponibilidad();
  }

  Future<void> _cargarDisponibilidad() async {
    try {
      final data =
          await widget.service.obtenerDisponibilidad(widget.producto.id);
      if (mounted) {
        setState(() {
          _disponibilidad = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'No se pudo cargar la disponibilidad';
          _isLoading = false;
        });
      }
    }
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 600,
          maxHeight: MediaQuery.of(context).size.height * 0.90,
        ),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            top: false,
            child: _isLoading
                ? const SizedBox(
                    height: 350,
                    child: Center(
                      child: CircularProgressIndicator(),
                    ),
                  )
                : _errorMessage != null
                    ? Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline,
                                size: 48, color: Colors.red),
                            const SizedBox(height: 12),
                            Text(_errorMessage!,
                                style: const TextStyle(fontSize: 16)),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  _isLoading = true;
                                  _errorMessage = null;
                                });
                                _cargarDisponibilidad();
                              },
                              child: const Text('Reintentar'),
                            ),
                          ],
                        ),
                      )
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 1. HEADER del producto
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 72,
                                  height: 72,
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade50,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Hero(
                                    tag: 'producto_${widget.producto.id}',
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: (widget.producto.imagenUrl != null &&
                                              widget.producto.imagenUrl!.isNotEmpty)
                                          ? Image.network(
                                              widget.producto.imagenUrl!,
                                              width: 72,
                                              height: 72,
                                              fit: BoxFit.cover,
                                              loadingBuilder:
                                                  (ctx, child, progress) =>
                                                      progress == null
                                                          ? child
                                                          : const Center(
                                                              child: CircularProgressIndicator(
                                                                  strokeWidth: 2),
                                                            ),
                                              errorBuilder:
                                                  (context, error, stackTrace) =>
                                                      Icon(
                                                Icons.checkroom,
                                                size: 48,
                                                color: primaryColor,
                                              ),
                                            )
                                          : Icon(
                                              Icons.checkroom,
                                              size: 48,
                                              color: primaryColor,
                                            ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        widget.producto.nombre,
                                        style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade200,
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          widget.producto.categoriaNombre,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade800,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),

                            if (widget.producto.descripcion != null &&
                                widget.producto.descripcion!.isNotEmpty) ...[
                              const SizedBox(height: 14),
                              Text(
                                widget.producto.descripcion!,
                                style: TextStyle(
                                  color: Colors.grey.shade700,
                                  fontSize: 14,
                                  height: 1.4,
                                ),
                              ),
                            ],

                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '\$${widget.producto.precio.toStringAsFixed(2)}',
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: primaryColor,
                                  ),
                                ),
                                _buildStatusBadge(widget.producto.estadoGlobal),
                              ],
                            ),

                            const Divider(height: 32),

                            // 2. RESUMEN GLOBAL
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.grey.shade200),
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceAround,
                                children: [
                                  Column(
                                    children: [
                                      const Text(
                                        'Stock total',
                                        style: TextStyle(
                                            fontSize: 12, color: Colors.grey),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${_disponibilidad?.totalGlobal ?? widget.producto.totalDisponible} unidades',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Container(
                                      width: 1,
                                      height: 32,
                                      color: Colors.grey.shade300),
                                  Column(
                                    children: [
                                      const Text(
                                        'Disponibilidad',
                                        style: TextStyle(
                                            fontSize: 12, color: Colors.grey),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${_disponibilidad?.sucursalesConStock ?? widget.producto.sucursalesConStock} de ${_disponibilidad?.disponibilidad.length ?? 0} sucursales',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 20),

                            // 3. LISTA DE SUCURSALES
                            const Text(
                              'Disponibilidad por sucursal',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),

                            if (_disponibilidad?.disponibilidad == null ||
                                _disponibilidad!.disponibilidad.isEmpty)
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                child: Text(
                                  'No hay información de sucursales disponible.',
                                  style: TextStyle(color: Colors.grey.shade600),
                                ),
                              )
                            else
                              ..._disponibilidad!.disponibilidad.map(
                                (sucursal) => Card(
                                  margin: const EdgeInsets.only(bottom: 14),
                                  elevation: 1,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    side: BorderSide(
                                        color: Colors.grey.shade200),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(14.0),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // Encabezado Sucursal
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    sucursal.nombreSucursal,
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 15,
                                                    ),
                                                  ),
                                                  if (sucursal.ciudad != null &&
                                                      sucursal.ciudad!.isNotEmpty)
                                                    Text(
                                                      sucursal.ciudad!,
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color: Colors
                                                            .grey.shade600,
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                            _buildStatusBadge(sucursal.estado),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          '${sucursal.totalDisponible} unidades',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.grey.shade700,
                                          ),
                                        ),
                                        const SizedBox(height: 12),

                                        // Items (Talla / Color) en Wrap
                                        if (sucursal.items.isEmpty)
                                          Text(
                                            'Sin items registrados',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade500,
                                            ),
                                          )
                                        else
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            children: sucursal.items.map((item) {
                                              final tieneStock =
                                                  item.cantidadDisponible > 0;
                                              final label =
                                                  'Talla ${item.nombreTalla ?? "-"} / ${item.nombreColor ?? "-"} — ${item.cantidadDisponible} un.';

                                              return Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 10,
                                                        vertical: 6),
                                                decoration: BoxDecoration(
                                                  color: tieneStock
                                                      ? Colors.blue.shade50
                                                      : Colors.grey.shade100,
                                                  borderRadius:
                                                      BorderRadius.circular(20),
                                                  border: Border.all(
                                                    color: tieneStock
                                                        ? Colors.blue.shade200
                                                        : Colors.grey.shade300,
                                                  ),
                                                ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Text(
                                                      label,
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color: tieneStock
                                                            ? Colors
                                                                .blue.shade900
                                                            : Colors
                                                                .grey.shade500,
                                                        decoration: tieneStock
                                                            ? null
                                                            : TextDecoration
                                                                .lineThrough,
                                                      ),
                                                    ),
                                                    if (tieneStock) ...[
                                                      const SizedBox(width: 8),
                                                      InkWell(
                                                        onTap: () async {
                                                          final created =
                                                              await showModalBottomSheet<
                                                                  bool>(
                                                            context: context,
                                                            isScrollControlled:
                                                                true,
                                                            backgroundColor:
                                                                Colors
                                                                    .transparent,
                                                            builder: (ctx) =>
                                                                MiniModalReserva(
                                                              productoId: widget
                                                                  .producto.id,
                                                              nombreProducto:
                                                                  widget
                                                                      .producto
                                                                      .nombre,
                                                              sucursalId:
                                                                  sucursal
                                                                      .sucursalId,
                                                              nombreSucursal:
                                                                  sucursal
                                                                      .nombreSucursal,
                                                              tallaId: item
                                                                      .tallaId ??
                                                                  0,
                                                              nombreTalla: item
                                                                  .nombreTalla,
                                                              colorId: item
                                                                      .colorId ??
                                                                  0,
                                                              nombreColor: item
                                                                  .nombreColor,
                                                              disponibleMax: item
                                                                  .cantidadDisponible,
                                                            ),
                                                          );

                                                          if (created == true &&
                                                              mounted) {
                                                            setState(() {
                                                              _isLoading = true;
                                                            });
                                                            _cargarDisponibilidad();
                                                          }
                                                        },
                                                        child: Container(
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                                  horizontal: 8,
                                                                  vertical: 3),
                                                          decoration:
                                                              BoxDecoration(
                                                            color: Colors
                                                                .blue.shade700,
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        12),
                                                          ),
                                                          child: const Text(
                                                            'Reservar',
                                                            style: TextStyle(
                                                              color: Colors
                                                                  .white,
                                                              fontSize: 11,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 6),
                                                      InkWell(
                                                        onTap: () {
                                                          context
                                                              .read<
                                                                  CarritoProvider>()
                                                              .agregar(
                                                                CarritoItem(
                                                                  productoId:
                                                                      widget
                                                                          .producto
                                                                          .id,
                                                                  nombreProducto:
                                                                      widget
                                                                          .producto
                                                                          .nombre,
                                                                  precio: widget
                                                                      .producto
                                                                      .precio,
                                                                  imagenUrl: widget
                                                                      .producto
                                                                      .imagenUrl,
                                                                  tallaId: item
                                                                      .tallaId,
                                                                  nombreTalla:
                                                                      item.nombreTalla,
                                                                  colorId: item
                                                                      .colorId,
                                                                  nombreColor:
                                                                      item.nombreColor,
                                                                  cantidad: 1,
                                                                  maxDisponible:
                                                                      item.cantidadDisponible,
                                                                ),
                                                              );
                                                          final messenger =
                                                              ScaffoldMessenger
                                                                  .of(context);
                                                          final router =
                                                              GoRouter.of(
                                                                  context);
                                                          messenger
                                                              .showSnackBar(
                                                            SnackBar(
                                                              content: Text(
                                                                'Añadido: ${widget.producto.nombre} (${item.nombreTalla ?? "-"} / ${item.nombreColor ?? "-"})',
                                                              ),
                                                              backgroundColor:
                                                                  Colors
                                                                      .green
                                                                      .shade700,
                                                              action:
                                                                  SnackBarAction(
                                                                label:
                                                                    'Ver carrito',
                                                                textColor:
                                                                    Colors
                                                                        .white,
                                                                onPressed:
                                                                    () =>
                                                                        router
                                                                            .push(
                                                                                '/carrito'),
                                                              ),
                                                            ),
                                                          );
                                                        },
                                                        child: Container(
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                                  horizontal: 8,
                                                                  vertical: 3),
                                                          decoration:
                                                              BoxDecoration(
                                                            color: Colors
                                                                .green.shade700,
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        12),
                                                          ),
                                                          child: const Row(
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .min,
                                                            children: [
                                                              Icon(
                                                                Icons
                                                                    .add_shopping_cart,
                                                                color: Colors
                                                                    .white,
                                                                size: 11,
                                                              ),
                                                              SizedBox(
                                                                  width: 3),
                                                              Text(
                                                                'Carrito',
                                                                style:
                                                                    TextStyle(
                                                                  color: Colors
                                                                      .white,
                                                                  fontSize:
                                                                      11,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              );
                                            }).toList(),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),

                            const SizedBox(height: 16),

                            // 4. BOTONES DE ACCIÓN: Cerrar + Añadir al carrito
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () => Navigator.pop(context),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 14),
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10),
                                      ),
                                    ),
                                    child: const Text(
                                      'Cerrar',
                                      style: TextStyle(fontSize: 15),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  flex: 2,
                                  child: ElevatedButton.icon(
                                    onPressed: () =>
                                        _abrirModalVariante(context),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green.shade700,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 14),
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10),
                                      ),
                                    ),
                                    icon: const Icon(Icons.add_shopping_cart,
                                        size: 20),
                                    label: const Text(
                                      'Añadir al carrito',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.indigo.shade800,
                                  side: BorderSide(
                                      color: Colors.indigo.shade300),
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                onPressed: () {
                                  Navigator.pop(context);
                                  context.push('/vestidor?productoId=${widget.producto.id}');
                                },
                                icon: const Icon(Icons.view_in_ar, size: 20),
                                label: const Text(
                                  'Probar en Vestidor Virtual AR',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
          ),
        ),
      ),
    );
  }

  void _abrirModalVariante(BuildContext context) {
    final mapVariantes = <String, DisponibilidadTallaColor>{};
    for (final suc in _disponibilidad?.disponibilidad ?? <DisponibilidadSucursal>[]) {
      for (final item in suc.items) {
        if (item.cantidadDisponible > 0) {
          final key = '${item.tallaId}_${item.colorId}';
          if (!mapVariantes.containsKey(key) ||
              item.cantidadDisponible > mapVariantes[key]!.cantidadDisponible) {
            mapVariantes[key] = item;
          }
        }
      }
    }

    final variantes = mapVariantes.values.toList();
    if (variantes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay stock disponible para añadir al carrito.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        var selectedItem = variantes.first;
        var cantidad = 1;

        return StatefulBuilder(
          builder: (context, setModalState) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  padding: const EdgeInsets.all(20.0),
                  child: SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Seleccionar Variante',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () => Navigator.pop(ctx),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          widget.producto.nombre,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        Text(
                          '\$${widget.producto.precio.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const Divider(height: 24),
                        const Text(
                          'Talla y Color:',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<DisponibilidadTallaColor>(
                          initialValue: selectedItem,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                          ),
                          items: variantes.map((v) {
                            return DropdownMenuItem<DisponibilidadTallaColor>(
                              value: v,
                              child: Text(
                                'Talla ${v.nombreTalla ?? "-"} / Color ${v.nombreColor ?? "-"} (${v.cantidadDisponible} disponibles)',
                                style: const TextStyle(fontSize: 13),
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setModalState(() {
                                selectedItem = val;
                                if (cantidad > val.cantidadDisponible) {
                                  cantidad = val.cantidadDisponible;
                                }
                              });
                            }
                          },
                        ),
                        const SizedBox(height: 18),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Cantidad:',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: Colors.grey.shade300),
                              ),
                              child: Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.remove, size: 18),
                                    onPressed: cantidad > 1
                                        ? () {
                                            setModalState(() => cantidad--);
                                          }
                                        : null,
                                  ),
                                  Text(
                                    '$cantidad',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.add, size: 18),
                                    onPressed: cantidad <
                                            selectedItem.cantidadDisponible
                                        ? () {
                                            setModalState(() => cantidad++);
                                          }
                                        : null,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green.shade700,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onPressed: () {
                              final itemCarrito = CarritoItem(
                                productoId: widget.producto.id,
                                nombreProducto: widget.producto.nombre,
                                precio: widget.producto.precio,
                                imagenUrl: widget.producto.imagenUrl,
                                tallaId: selectedItem.tallaId,
                                nombreTalla: selectedItem.nombreTalla,
                                colorId: selectedItem.colorId,
                                nombreColor: selectedItem.nombreColor,
                                cantidad: cantidad,
                                maxDisponible:
                                    selectedItem.cantidadDisponible,
                              );
                              final messenger = ScaffoldMessenger.of(context);
                              final router = GoRouter.of(context);
                              context
                                  .read<CarritoProvider>()
                                  .agregar(itemCarrito);
                              Navigator.pop(ctx);
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '${cantidad}x "${widget.producto.nombre}" agregado al carrito',
                                  ),
                                  backgroundColor: Colors.green.shade700,
                                  action: SnackBarAction(
                                    label: 'Ver carrito',
                                    textColor: Colors.white,
                                    onPressed: () =>
                                        router.push('/carrito'),
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.add_shopping_cart),
                            label: Text(
                              'Añadir al carrito • \$${(widget.producto.precio * cantidad).toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
