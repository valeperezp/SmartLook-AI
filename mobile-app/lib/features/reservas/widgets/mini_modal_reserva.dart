import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../core/models/reserva.dart';
import '../../../core/utils/app_notifications.dart';
import '../providers/reservas_provider.dart';

class MiniModalReserva extends StatefulWidget {
  final int productoId;
  final String nombreProducto;
  final int sucursalId;
  final String nombreSucursal;
  final int tallaId;
  final String? nombreTalla;
  final int colorId;
  final String? nombreColor;
  final int disponibleMax;

  const MiniModalReserva({
    super.key,
    required this.productoId,
    required this.nombreProducto,
    required this.sucursalId,
    required this.nombreSucursal,
    required this.tallaId,
    this.nombreTalla,
    required this.colorId,
    this.nombreColor,
    required this.disponibleMax,
  });

  @override
  State<MiniModalReserva> createState() => _MiniModalReservaState();
}

class _MiniModalReservaState extends State<MiniModalReserva> {
  final _formKey = GlobalKey<FormState>();
  final _cantidadController = TextEditingController(text: '1');
  DateTime? _horarioAproximado;

  @override
  void dispose() {
    _cantidadController.dispose();
    super.dispose();
  }

  Future<void> _seleccionarHorario() async {
    final now = DateTime.now();
    final fecha = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 30)),
    );

    if (fecha == null || !mounted) return;

    final hora = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 2))),
    );

    if (hora == null || !mounted) return;

    setState(() {
      _horarioAproximado = DateTime(
        fecha.year,
        fecha.month,
        fecha.day,
        hora.hour,
        hora.minute,
      );
    });
  }

  Future<void> _confirmarReserva() async {
    if (!_formKey.currentState!.validate()) return;

    final cantidad = int.tryParse(_cantidadController.text.trim()) ?? 1;

    final data = ReservaCreate(
      sucursalId: widget.sucursalId,
      horarioAproximado: _horarioAproximado,
      items: [
        ReservaItemCreate(
          productoId: widget.productoId,
          tallaId: widget.tallaId,
          colorId: widget.colorId,
          cantidad: cantidad,
        ),
      ],
    );

    final provider = context.read<ReservasProvider>();
    final success = await provider.crearReserva(data);

    if (!mounted) return;

    if (success) {
      final reservaId = provider.ultimaReservaCreada?.id;
      Navigator.pop(context, true);
      AppNotifications.success(
        context,
        'Reserva #${reservaId ?? ""} creada con éxito',
      );
    } else {
      AppNotifications.error(
        context,
        provider.errorMessage ?? 'Error al crear la reserva',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reservas = context.watch<ReservasProvider>();

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 500,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.all(20.0),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. Header
                    Row(
                      children: [
                        Icon(Icons.bookmark_add,
                            color: theme.colorScheme.primary, size: 28),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Confirmar reserva',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.nombreProducto,
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Divider(height: 24),

                    // 2. Info de variante y sucursal
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.storefront,
                                  size: 18, color: Colors.blue),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Sucursal: ${widget.nombreSucursal}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.checkroom,
                                  size: 18, color: Colors.blue),
                              const SizedBox(width: 6),
                              Text(
                                'Talla: ${widget.nombreTalla ?? "-"}  |  Color: ${widget.nombreColor ?? "-"}',
                                style: TextStyle(color: Colors.grey.shade800),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.inventory,
                                  size: 18, color: Colors.blue),
                              const SizedBox(width: 6),
                              Text(
                                'Disponible: ${widget.disponibleMax} unidades',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // 3. Formulario (Cantidad + Horario)
                    TextFormField(
                      controller: _cantidadController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Cantidad a reservar',
                        prefixIcon: const Icon(Icons.shopping_bag_outlined),
                        helperText: 'Máximo disponible: ${widget.disponibleMax}',
                        border: const OutlineInputBorder(),
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) {
                          return 'Ingresa una cantidad';
                        }
                        final numVal = int.tryParse(val.trim());
                        if (numVal == null || numVal < 1) {
                          return 'La cantidad mínima es 1';
                        }
                        if (numVal > widget.disponibleMax) {
                          return 'Solo hay ${widget.disponibleMax} unidades disponibles';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Horario aproximado (opcional)
                    InkWell(
                      onTap: _seleccionarHorario,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.calendar_today_outlined,
                                size: 20, color: theme.colorScheme.primary),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Horario estimado de visita (opcional)',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _horarioAproximado != null
                                        ? DateFormat('dd/MM/yyyy HH:mm')
                                            .format(_horarioAproximado!)
                                        : 'Seleccionar fecha y hora',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: _horarioAproximado != null
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (_horarioAproximado != null)
                              IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  setState(() {
                                    _horarioAproximado = null;
                                  });
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // 4. Botones
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: reservas.isLoading
                                ? null
                                : () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: const Text('Cancelar'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            onPressed:
                                reservas.isLoading ? null : _confirmarReserva,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: theme.colorScheme.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: reservas.isLoading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text(
                                    'Confirmar reserva',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
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
      ),
    );
  }
}
