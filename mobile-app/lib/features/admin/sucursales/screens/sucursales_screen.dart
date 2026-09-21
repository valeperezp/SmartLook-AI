import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../../core/models/sucursal.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/loading_state.dart';
import '../providers/sucursales_admin_provider.dart';
import '../widgets/sucursal_tile.dart';

class SucursalesScreen extends StatefulWidget {
  const SucursalesScreen({super.key});

  @override
  State<SucursalesScreen> createState() => _SucursalesScreenState();
}

class _SucursalesScreenState extends State<SucursalesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SucursalesAdminProvider>().cargarSucursales();
    });
  }

  void _confirmarDesactivar(BuildContext context, Sucursal sucursal) {
    final messenger = ScaffoldMessenger.of(context);
    final prov = context.read<SucursalesAdminProvider>();

    showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('¿Desactivar sucursal?'),
        content: Text(
          'La sucursal "${sucursal.nombre}" quedará inactiva y no podrá recibir pedidos ni reservas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Desactivar'),
          ),
        ],
      ),
    ).then((confirmado) async {
      if (confirmado == true) {
        final ok = await prov.desactivarSucursal(sucursal.id);
        if (ok) {
          messenger.showSnackBar(
            SnackBar(
              content: Text('Sucursal "${sucursal.nombre}" desactivada'),
              backgroundColor: Colors.green.shade700,
            ),
          );
        } else {
          messenger.showSnackBar(
            SnackBar(
              content: Text(prov.errorMessage ?? 'Error al desactivar sucursal'),
              backgroundColor: Colors.red.shade700,
            ),
          );
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<SucursalesAdminProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Gestión de Sucursales',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.indigo.shade800,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.go('/admin'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'Actualizar',
            onPressed: prov.isLoading ? null : () => prov.cargarSucursales(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.indigo.shade700,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text(
          'Nueva sucursal',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        onPressed: () => context.push('/admin/sucursales/form'),
      ),
      body: prov.isLoading && prov.sucursales.isEmpty
          ? const LoadingState(mensaje: 'Cargando sucursales...')
          : prov.errorMessage != null && prov.sucursales.isEmpty
              ? EmptyState(
                  icono: Icons.error_outline,
                  titulo: 'Error al cargar sucursales',
                  mensaje: prov.errorMessage,
                  onReintentar: () => prov.cargarSucursales(),
                )
              : prov.sucursales.isEmpty
                  ? EmptyState(
                      icono: Icons.storefront_outlined,
                      titulo: 'No hay sucursales registradas',
                      mensaje: 'Presiona el botón para crear la primera sucursal.',
                      textoBoton: 'Crear sucursal',
                      onReintentar: () => context.push('/admin/sucursales/form'),
                    )
                  : RefreshIndicator(
                      onRefresh: () => prov.cargarSucursales(),
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                        itemCount: prov.sucursales.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final sucursal = prov.sucursales[index];
                          return SucursalTile(
                            sucursal: sucursal,
                            onEditar: () => context.push(
                              '/admin/sucursales/form',
                              extra: sucursal,
                            ),
                            onDesactivar: () =>
                                _confirmarDesactivar(context, sucursal),
                          );
                        },
                      ),
                    ),
    );
  }
}
