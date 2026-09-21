import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/loading_state.dart';
import '../models/promocion.dart';
import '../providers/promociones_provider.dart';
import '../widgets/promocion_tile.dart';

class PromocionesScreen extends StatefulWidget {
  const PromocionesScreen({super.key});

  @override
  State<PromocionesScreen> createState() => _PromocionesScreenState();
}

class _PromocionesScreenState extends State<PromocionesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PromocionesProvider>().cargarPromociones();
    });
  }

  void _confirmarToggleActivo(BuildContext context, Promocion promo) {
    final messenger = ScaffoldMessenger.of(context);
    final prov = context.read<PromocionesProvider>();
    final accion = promo.activo ? 'desactivar' : 'reactivar';

    showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('¿Desea $accion la promoción?'),
        content: Text(
          promo.activo
              ? 'La promoción "${promo.nombre}" ya no se aplicará a nuevas ventas.'
              : 'La promoción "${promo.nombre}" volverá a estar disponible.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  promo.activo ? Colors.orange.shade800 : Colors.teal.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: Text(promo.activo ? 'Desactivar' : 'Reactivar'),
          ),
        ],
      ),
    ).then((confirmado) async {
      if (confirmado == true) {
        final ok = promo.activo
            ? await prov.desactivarPromocion(promo.id)
            : await prov.reactivarPromocion(promo.id);
        if (ok) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                'Promoción ${promo.activo ? "desactivada" : "reactivada"} con éxito',
              ),
              backgroundColor: Colors.green.shade700,
            ),
          );
        } else {
          messenger.showSnackBar(
            SnackBar(
              content: Text(prov.errorMessage ?? 'Ocurrió un error'),
              backgroundColor: Colors.red.shade700,
            ),
          );
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<PromocionesProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Promociones y Descuentos',
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
            onPressed: prov.isLoading ? null : () => prov.cargarPromociones(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.indigo.shade700,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text(
          'Nueva promoción',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        onPressed: () => context.push('/admin/promociones/form'),
      ),
      body: Column(
        children: [
          // Barra de Filtro Activas / Todas
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            color: AppTheme.surface,
            child: Row(
              children: [
                const Text(
                  'Filtro: ',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Todas'),
                  selected: !prov.soloActivas,
                  selectedColor: AppTheme.primary,
                  labelStyle: TextStyle(
                    color: !prov.soloActivas ? Colors.white : AppTheme.textPrimary,
                    fontWeight: !prov.soloActivas
                        ? FontWeight.bold
                        : FontWeight.normal,
                    fontSize: 12,
                  ),
                  onSelected: (val) {
                    if (val) prov.cambiarFiltroActivas(false);
                  },
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Solo Activas'),
                  selected: prov.soloActivas,
                  selectedColor: AppTheme.primary,
                  labelStyle: TextStyle(
                    color: prov.soloActivas ? Colors.white : AppTheme.textPrimary,
                    fontWeight:
                        prov.soloActivas ? FontWeight.bold : FontWeight.normal,
                    fontSize: 12,
                  ),
                  onSelected: (val) {
                    if (val) prov.cambiarFiltroActivas(true);
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Lista de promociones
          Expanded(
            child: prov.isLoading && prov.promociones.isEmpty
                ? const LoadingState(mensaje: 'Cargando promociones...')
                : prov.errorMessage != null && prov.promociones.isEmpty
                    ? EmptyState(
                        icono: Icons.error_outline,
                        titulo: 'Error al cargar',
                        mensaje: prov.errorMessage,
                        onReintentar: () => prov.cargarPromociones(),
                      )
                    : prov.promociones.isEmpty
                        ? EmptyState(
                            icono: Icons.local_offer_outlined,
                            titulo: 'No hay promociones',
                            mensaje: prov.soloActivas
                                ? 'No se encontraron promociones activas actualmente.'
                                : 'Aún no se ha creado ninguna promoción.',
                            textoBoton: 'Crear promoción',
                            onReintentar: () =>
                                context.push('/admin/promociones/form'),
                          )
                        : RefreshIndicator(
                            onRefresh: () => prov.cargarPromociones(),
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                              itemCount: prov.promociones.length,
                              separatorBuilder: (context, index) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                final promo = prov.promociones[index];
                                return PromocionTile(
                                  promocion: promo,
                                  onEditar: () => context.push(
                                    '/admin/promociones/form',
                                    extra: promo,
                                  ),
                                  onToggleActivo: () =>
                                      _confirmarToggleActivo(context, promo),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}
