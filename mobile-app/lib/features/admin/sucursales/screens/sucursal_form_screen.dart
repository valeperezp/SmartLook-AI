import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../../core/models/sucursal.dart';
import '../../../../core/theme/app_theme.dart';
import '../providers/sucursales_admin_provider.dart';

class SucursalFormScreen extends StatefulWidget {
  final Sucursal? sucursal;

  const SucursalFormScreen({super.key, this.sucursal});

  @override
  State<SucursalFormScreen> createState() => _SucursalFormScreenState();
}

class _SucursalFormScreenState extends State<SucursalFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nombreCtrl;
  late TextEditingController _direccionCtrl;
  late TextEditingController _ciudadCtrl;
  late TextEditingController _telefonoCtrl;

  late bool _activa;

  @override
  void initState() {
    super.initState();
    final s = widget.sucursal;
    _nombreCtrl = TextEditingController(text: s?.nombre ?? '');
    _direccionCtrl = TextEditingController(text: s?.direccion ?? '');
    _ciudadCtrl = TextEditingController(text: s?.ciudad ?? '');
    _telefonoCtrl = TextEditingController(text: s?.telefono ?? '');
    _activa = s?.activa ?? true;
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _direccionCtrl.dispose();
    _ciudadCtrl.dispose();
    _telefonoCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final prov = context.read<SucursalesAdminProvider>();

    final Map<String, dynamic> datos = {
      'nombre': _nombreCtrl.text.trim(),
      'direccion': _direccionCtrl.text.trim(),
      'ciudad': _ciudadCtrl.text.trim().isEmpty ? null : _ciudadCtrl.text.trim(),
      'telefono':
          _telefonoCtrl.text.trim().isEmpty ? null : _telefonoCtrl.text.trim(),
    };

    bool exito = false;
    if (widget.sucursal == null) {
      exito = await prov.crearSucursal(datos);
    } else {
      datos['activa'] = _activa;
      exito = await prov.actualizarSucursal(widget.sucursal!.id, datos);
    }

    if (exito) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            widget.sucursal == null
                ? 'Sucursal creada exitosamente'
                : 'Sucursal actualizada con éxito',
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
    final esEdicion = widget.sucursal != null;
    final prov = context.watch<SucursalesAdminProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          esEdicion ? 'Editar Sucursal' : 'Nueva Sucursal',
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
            constraints: const BoxConstraints(maxWidth: 650),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                            'Datos de la Sucursal',
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
                              labelText: 'Nombre de la sucursal *',
                              hintText: 'Ej: Sucursal Central, Sucursal Norte',
                              prefixIcon: Icon(Icons.storefront),
                              border: OutlineInputBorder(),
                            ),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'El nombre es obligatorio';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),

                          // Dirección
                          TextFormField(
                            controller: _direccionCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Dirección física *',
                              hintText: 'Ej: Av. Principal 123',
                              prefixIcon: Icon(Icons.location_on_outlined),
                              border: OutlineInputBorder(),
                            ),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'La dirección es obligatoria';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),

                          // Ciudad
                          TextFormField(
                            controller: _ciudadCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Ciudad (opcional)',
                              hintText: 'Ej: Santiago, Concepción, etc.',
                              prefixIcon: Icon(Icons.location_city),
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Teléfono
                          TextFormField(
                            controller: _telefonoCtrl,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(
                              labelText: 'Teléfono de contacto (opcional)',
                              hintText: 'Ej: +56 9 1234 5678',
                              prefixIcon: Icon(Icons.phone_outlined),
                              border: OutlineInputBorder(),
                            ),
                          ),

                          if (esEdicion) ...[
                            const SizedBox(height: 16),
                            SwitchListTile(
                              title: const Text('Sucursal Activa'),
                              subtitle: const Text(
                                'Indica si la sucursal está disponible para ventas y reservas',
                              ),
                              value: _activa,
                              activeTrackColor: AppTheme.primary,
                              onChanged: (val) => setState(() => _activa = val),
                            ),
                          ],
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
                            prov.isSaving ? 'Guardando...' : 'Guardar sucursal',
                          ),
                          onPressed: prov.isSaving ? null : _guardar,
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
