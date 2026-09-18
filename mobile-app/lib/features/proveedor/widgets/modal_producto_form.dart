import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/proveedor_provider.dart';
import '../../../core/utils/app_notifications.dart';

class ModalProductoForm extends StatefulWidget {
  final Map<String, dynamic>? producto;
  final List<dynamic> categorias;
  final List<dynamic> temporadas;
  final List<dynamic> colecciones;

  const ModalProductoForm({
    super.key,
    this.producto,
    required this.categorias,
    required this.temporadas,
    required this.colecciones,
  });

  @override
  State<ModalProductoForm> createState() => _ModalProductoFormState();
}

class _ModalProductoFormState extends State<ModalProductoForm> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nombreController;
  late final TextEditingController _descripcionController;
  late final TextEditingController _precioController;
  late final TextEditingController _modeloArUrlController;

  int? _selectedCategoriaId;
  int? _selectedTemporadaId;
  int? _selectedColeccionId;

  bool _isSubmitting = false;

  bool get _isEdicion => widget.producto != null;

  @override
  void initState() {
    super.initState();
    final prod = widget.producto;

    _nombreController = TextEditingController(text: prod?['nombre']?.toString() ?? '');
    _descripcionController = TextEditingController(text: prod?['descripcion']?.toString() ?? '');
    _precioController = TextEditingController(
      text: prod?['precio'] != null ? prod!['precio'].toString() : '',
    );
    _modeloArUrlController = TextEditingController(
      text: prod?['modelo_ar_url']?.toString() ?? '',
    );

    // Resolver selección inicial de categoría
    final initialCatId = prod?['categoria_id'] ?? prod?['categoria']?['id'];
    if (initialCatId != null &&
        widget.categorias.any((c) => c['id'] == initialCatId)) {
      _selectedCategoriaId = initialCatId as int;
    } else if (widget.categorias.isNotEmpty && !_isEdicion) {
      _selectedCategoriaId = widget.categorias.first['id'] as int;
    }

    // Resolver selección inicial de temporada
    final initialTempId = prod?['temporada_id'] ?? prod?['temporada']?['id'];
    if (initialTempId != null &&
        widget.temporadas.any((t) => t['id'] == initialTempId)) {
      _selectedTemporadaId = initialTempId as int;
    }

    // Resolver selección inicial de colección
    final initialColId = prod?['coleccion_id'] ?? prod?['coleccion']?['id'];
    if (initialColId != null &&
        widget.colecciones.any((c) => c['id'] == initialColId)) {
      _selectedColeccionId = initialColId as int;
    }
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _descripcionController.dispose();
    _precioController.dispose();
    _modeloArUrlController.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedCategoriaId == null) {
      AppNotifications.warning(context, 'Debe seleccionar una categoría');
      return;
    }

    final precio = double.tryParse(_precioController.text.trim().replaceAll(',', '.'));
    if (precio == null || precio < 0) {
      AppNotifications.warning(context, 'Ingrese un precio válido mayor o igual a 0');
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    final Map<String, dynamic> data = {
      'nombre': _nombreController.text.trim(),
      'descripcion': _descripcionController.text.trim().isEmpty
          ? null
          : _descripcionController.text.trim(),
      'precio': precio,
      'categoria_id': _selectedCategoriaId,
      'temporada_id': _selectedTemporadaId,
      'coleccion_id': _selectedColeccionId,
      'modelo_ar_url': _modeloArUrlController.text.trim().isEmpty
          ? null
          : _modeloArUrlController.text.trim(),
    };

    final provider = context.read<ProveedorProvider>();
    bool success = false;

    if (_isEdicion) {
      final int prodId = widget.producto!['id'] as int;
      success = await provider.actualizarProducto(prodId, data);
    } else {
      success = await provider.crearProducto(data);
    }

    if (!mounted) return;

    setState(() {
      _isSubmitting = false;
    });

    if (success) {
      Navigator.of(context).pop(true);
      AppNotifications.success(
        context,
        _isEdicion ? 'Producto actualizado' : 'Producto creado',
      );
    } else {
      AppNotifications.error(
        context,
        provider.errorMessage ??
            (_isEdicion ? 'Error al actualizar producto' : 'Error al crear producto'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Container(
        padding: const EdgeInsets.all(20.0),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Header con título y botón de cerrar (X)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _isEdicion ? 'Editar producto' : 'Nuevo producto',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal.shade900,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(false),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Divider(),
              const SizedBox(height: 12),

              // 2. Campo Nombre (required, max 150 chars)
              TextFormField(
                controller: _nombreController,
                maxLength: 150,
                decoration: const InputDecoration(
                  labelText: 'Nombre *',
                  hintText: 'Ej. Camisa de Lino Manga Larga',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'El nombre es obligatorio';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 10),

              // 3. Campo Descripción (opcional, max 500 chars, multiline)
              TextFormField(
                controller: _descripcionController,
                maxLength: 500,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Descripción (opcional)',
                  hintText: 'Detalles del material, corte, cuidados...',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
              const SizedBox(height: 10),

              // 4. Campo Precio (required, min 0)
              TextFormField(
                controller: _precioController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Precio *',
                  hintText: '0.00',
                  prefixText: '\$ ',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'El precio es obligatorio';
                  }
                  final val = double.tryParse(value.trim().replaceAll(',', '.'));
                  if (val == null || val < 0) {
                    return 'Ingrese un número válido mayor o igual a 0';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // 5. Dropdown Categoría (required)
              DropdownButtonFormField<int>(
                initialValue: _selectedCategoriaId,
                decoration: const InputDecoration(
                  labelText: 'Categoría *',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                items: widget.categorias.map<DropdownMenuItem<int>>((cat) {
                  return DropdownMenuItem<int>(
                    value: cat['id'] as int,
                    child: Text(cat['nombre']?.toString() ?? 'Cat ${cat['id']}'),
                  );
                }).toList(),
                onChanged: (val) {
                  setState(() {
                    _selectedCategoriaId = val;
                  });
                },
                validator: (val) => val == null ? 'Seleccione una categoría' : null,
              ),
              const SizedBox(height: 16),

              // 6. Dropdown Temporada (opcional)
              DropdownButtonFormField<int?>(
                initialValue: _selectedTemporadaId,
                decoration: const InputDecoration(
                  labelText: 'Temporada (opcional)',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('Ninguna'),
                  ),
                  ...widget.temporadas.map<DropdownMenuItem<int?>>((temp) {
                    return DropdownMenuItem<int?>(
                      value: temp['id'] as int,
                      child: Text(temp['nombre']?.toString() ?? 'Temporada ${temp['id']}'),
                    );
                  }),
                ],
                onChanged: (val) {
                  setState(() {
                    _selectedTemporadaId = val;
                  });
                },
              ),
              const SizedBox(height: 16),

              // 7. Dropdown Colección (opcional)
              DropdownButtonFormField<int?>(
                initialValue: _selectedColeccionId,
                decoration: const InputDecoration(
                  labelText: 'Colección (opcional)',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('Ninguna'),
                  ),
                  ...widget.colecciones.map<DropdownMenuItem<int?>>((col) {
                    return DropdownMenuItem<int?>(
                      value: col['id'] as int,
                      child: Text(col['nombre']?.toString() ?? 'Colección ${col['id']}'),
                    );
                  }),
                ],
                onChanged: (val) {
                  setState(() {
                    _selectedColeccionId = val;
                  });
                },
              ),
              const SizedBox(height: 16),

              // 8. Campo Modelo AR URL (opcional)
              TextFormField(
                controller: _modeloArUrlController,
                decoration: const InputDecoration(
                  labelText: 'Modelo AR URL (opcional)',
                  hintText: 'https://...',
                  prefixIcon: Icon(Icons.view_in_ar_outlined),
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
              const SizedBox(height: 20),

              // 9. Botones Cancelar y Guardar / Crear
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(false),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal.shade800,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: _isSubmitting ? null : _guardar,
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(_isEdicion ? 'Guardar' : 'Crear'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
