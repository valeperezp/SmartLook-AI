import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../models/promocion.dart';
import '../providers/promociones_provider.dart';
import '../services/promociones_service.dart';

class PromocionFormScreen extends StatefulWidget {
  final Promocion? promocion;

  const PromocionFormScreen({super.key, this.promocion});

  @override
  State<PromocionFormScreen> createState() => _PromocionFormScreenState();
}

class _PromocionFormScreenState extends State<PromocionFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nombreCtrl;
  late TextEditingController _descCtrl;
  late TextEditingController _valorCtrl;

  late String _tipo; // 'porcentaje' o 'monto_fijo'
  late DateTime _fechaInicio;
  late DateTime _fechaFin;

  List<Map<String, dynamic>> _productosDisponibles = [];
  Set<int> _productosSeleccionados = {};
  bool _cargandoProductos = false;
  String _filtroProducto = '';

  @override
  void initState() {
    super.initState();
    final p = widget.promocion;
    _nombreCtrl = TextEditingController(text: p?.nombre ?? '');
    _descCtrl = TextEditingController(text: p?.descripcion ?? '');
    _valorCtrl = TextEditingController(
      text: p != null ? p.valor.toString() : '',
    );
    _tipo = p?.tipo ?? 'porcentaje';

    if (p != null && p.fechaInicio.isNotEmpty) {
      try {
        _fechaInicio = DateTime.parse(p.fechaInicio);
      } catch (_) {
        _fechaInicio = DateTime.now();
      }
    } else {
      _fechaInicio = DateTime.now();
    }

    if (p != null && p.fechaFin.isNotEmpty) {
      try {
        _fechaFin = DateTime.parse(p.fechaFin);
      } catch (_) {
        _fechaFin = DateTime.now().add(const Duration(days: 30));
      }
    } else {
      _fechaFin = DateTime.now().add(const Duration(days: 30));
    }

    if (p != null) {
      _productosSeleccionados = p.productos.map((e) => e.productoId).toSet();
    }

    _cargarProductos();
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _descCtrl.dispose();
    _valorCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarProductos() async {
    setState(() => _cargandoProductos = true);
    try {
      final res = await DioClient().get('/catalogo/productos');
      final list = (res.data as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
      if (mounted) {
        setState(() {
          _productosDisponibles = list;
          _cargandoProductos = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _cargandoProductos = false);
      }
    }
  }

  Future<void> _seleccionarFecha(bool esInicio) async {
    final initialDate = esInicio ? _fechaInicio : _fechaFin;
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      setState(() {
        if (esInicio) {
          _fechaInicio = picked;
          if (_fechaFin.isBefore(_fechaInicio)) {
            _fechaFin = _fechaInicio.add(const Duration(days: 1));
          }
        } else {
          _fechaFin = picked;
        }
      });
    }
  }

  String _formatFecha(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final prov = context.read<PromocionesProvider>();

    final valor = double.tryParse(_valorCtrl.text.trim()) ?? 0.0;
    final fInicioStr = _formatFecha(_fechaInicio);
    final fFinStr = _formatFecha(_fechaFin);

    final datos = {
      'nombre': _nombreCtrl.text.trim(),
      'descripcion': _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      'tipo': _tipo,
      'valor': valor,
      'fecha_inicio': fInicioStr,
      'fecha_fin': fFinStr,
      'producto_ids': _productosSeleccionados.toList(),
    };

    bool exito = false;
    if (widget.promocion == null) {
      exito = await prov.crearPromocion(datos);
    } else {
      exito = await prov.actualizarPromocion(widget.promocion!.id, {
        'nombre': datos['nombre'],
        'descripcion': datos['descripcion'],
        'tipo': datos['tipo'],
        'valor': datos['valor'],
        'fecha_inicio': datos['fecha_inicio'],
        'fecha_fin': datos['fecha_fin'],
      });
      if (exito) {
        // Actualizar asociación de productos
        try {
          await PromocionesService().actualizarProductos(
            widget.promocion!.id,
            _productosSeleccionados.toList(),
          );
          await prov.cargarPromociones();
        } catch (_) {}
      }
    }

    if (exito) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            widget.promocion == null
                ? 'Promoción creada exitosamente'
                : 'Promoción actualizada con éxito',
          ),
          backgroundColor: Colors.green.shade700,
        ),
      );
      router.pop();
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(prov.errorMessage ?? 'Ocurrió un error al guardar'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final esEdicion = widget.promocion != null;
    final prov = context.watch<PromocionesProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          esEdicion ? 'Editar Promoción' : 'Nueva Promoción',
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.indigo.shade800,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Card datos básicos
                  Card(
                    color: AppTheme.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                      side: const BorderSide(color: AppTheme.border, width: 1),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Información de la promoción',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Nombre
                          TextFormField(
                            controller: _nombreCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Nombre de la promoción *',
                              hintText: 'Ej: Black Friday 20%, Descuento Verano',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.label_outline),
                            ),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'El nombre es obligatorio';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),

                          // Descripción
                          TextFormField(
                            controller: _descCtrl,
                            maxLines: 2,
                            decoration: const InputDecoration(
                              labelText: 'Descripción (opcional)',
                              hintText: 'Breve explicación de las condiciones del descuento',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.description_outlined),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Tipo de Descuento
                          const Text(
                            'Tipo de descuento',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: ChoiceChip(
                                  label: const Center(
                                    child: Text('Porcentaje (%)'),
                                  ),
                                  selected: _tipo == 'porcentaje',
                                  selectedColor: AppTheme.primary,
                                  labelStyle: TextStyle(
                                    color: _tipo == 'porcentaje'
                                        ? Colors.white
                                        : AppTheme.textPrimary,
                                    fontWeight: _tipo == 'porcentaje'
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                  onSelected: (val) {
                                    if (val) setState(() => _tipo = 'porcentaje');
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ChoiceChip(
                                  label: const Center(
                                    child: Text('Monto Fijo (\$)'),
                                  ),
                                  selected: _tipo == 'monto_fijo',
                                  selectedColor: AppTheme.primary,
                                  labelStyle: TextStyle(
                                    color: _tipo == 'monto_fijo'
                                        ? Colors.white
                                        : AppTheme.textPrimary,
                                    fontWeight: _tipo == 'monto_fijo'
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                  onSelected: (val) {
                                    if (val) setState(() => _tipo = 'monto_fijo');
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Valor
                          TextFormField(
                            controller: _valorCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText: _tipo == 'porcentaje'
                                  ? 'Porcentaje de descuento (%) *'
                                  : 'Monto a descontar (\$) *',
                              prefixIcon: Icon(
                                _tipo == 'porcentaje'
                                    ? Icons.percent
                                    : Icons.attach_money,
                              ),
                              border: const OutlineInputBorder(),
                            ),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'Ingrese el valor del descuento';
                              }
                              final num = double.tryParse(v.trim());
                              if (num == null || num <= 0) {
                                return 'Ingrese un valor numérico positivo';
                              }
                              if (_tipo == 'porcentaje' && num > 100) {
                                return 'El porcentaje no puede ser mayor a 100';
                              }
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Card fechas de vigencia
                  Card(
                    color: AppTheme.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                      side: const BorderSide(color: AppTheme.border, width: 1),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Período de vigencia',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: InkWell(
                                  onTap: () => _seleccionarFecha(true),
                                  child: InputDecorator(
                                    decoration: const InputDecoration(
                                      labelText: 'Fecha de inicio',
                                      border: OutlineInputBorder(),
                                      prefixIcon: Icon(Icons.calendar_today),
                                    ),
                                    child: Text(_formatFecha(_fechaInicio)),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: InkWell(
                                  onTap: () => _seleccionarFecha(false),
                                  child: InputDecorator(
                                    decoration: const InputDecoration(
                                      labelText: 'Fecha de fin',
                                      border: OutlineInputBorder(),
                                      prefixIcon: Icon(Icons.event),
                                    ),
                                    child: Text(_formatFecha(_fechaFin)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Card Selector de productos (opcional)
                  Card(
                    color: AppTheme.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                      side: const BorderSide(color: AppTheme.border, width: 1),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Productos incluidos',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                              Text(
                                _productosSeleccionados.isEmpty
                                    ? 'Aplica a todos'
                                    : '${_productosSeleccionados.length} seleccionados',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: _productosSeleccionados.isEmpty
                                      ? Colors.grey.shade600
                                      : AppTheme.primary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Si no selecciona ningún producto, la promoción aplicará como descuento general a todo el catálogo.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Buscador de productos
                          TextField(
                            decoration: InputDecoration(
                              hintText: 'Filtrar productos por nombre...',
                              prefixIcon: const Icon(Icons.search, size: 20),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                            ),
                            onChanged: (val) {
                              setState(() => _filtroProducto = val.toLowerCase());
                            },
                          ),
                          const SizedBox(height: 12),

                          // Lista seleccionable de productos
                          _cargandoProductos
                              ? const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(16.0),
                                    child: CircularProgressIndicator(),
                                  ),
                                )
                              : Container(
                                  height: 220,
                                  decoration: BoxDecoration(
                                    border: Border.all(color: AppTheme.border),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: ListView(
                                    children: _productosDisponibles
                                        .where((p) {
                                          if (_filtroProducto.isEmpty) return true;
                                          final name = (p['nombre'] ?? '')
                                              .toString()
                                              .toLowerCase();
                                          return name.contains(_filtroProducto);
                                        })
                                        .map((p) {
                                          final id = p['id'] as int;
                                          final nombre = p['nombre'] ?? 'Sin nombre';
                                          final precio = p['precio_base'] ?? p['precio'] ?? 0;
                                          final selected =
                                              _productosSeleccionados.contains(id);

                                          return CheckboxListTile(
                                            value: selected,
                                            title: Text(
                                              nombre.toString(),
                                              style: const TextStyle(fontSize: 13),
                                            ),
                                            subtitle: Text(
                                              '\$$precio',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey.shade600,
                                              ),
                                            ),
                                            dense: true,
                                            activeColor: AppTheme.primary,
                                            onChanged: (val) {
                                              setState(() {
                                                if (val == true) {
                                                  _productosSeleccionados.add(id);
                                                } else {
                                                  _productosSeleccionados.remove(id);
                                                }
                                              });
                                            },
                                          );
                                        })
                                        .toList(),
                                  ),
                                ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Botones Guardar / Cancelar
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: () => context.pop(),
                          child: const Text('Cancelar'),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            backgroundColor: Colors.indigo.shade700,
                            foregroundColor: Colors.white,
                          ),
                          icon: prov.isSaving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.save),
                          label: Text(
                            prov.isSaving ? 'Guardando...' : 'Guardar promoción',
                          ),
                          onPressed: prov.isSaving ? null : _guardar,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
