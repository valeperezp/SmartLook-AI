import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/loading_state.dart';
import '../providers/ventas_provider.dart';
import '../widgets/venta_tile.dart';

class MisComprasScreen extends StatefulWidget {
  const MisComprasScreen({super.key});

  @override
  State<MisComprasScreen> createState() => _MisComprasScreenState();
}

class _MisComprasScreenState extends State<MisComprasScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<VentasProvider>().cargarCompras();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Mis Compras',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.blue.shade700,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'Actualizar',
            onPressed: () => context.read<VentasProvider>().cargarCompras(),
          ),
        ],
      ),
      body: Consumer<VentasProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading && provider.compras.isEmpty) {
            return const LoadingState(mensaje: 'Cargando tus compras online...');
          }

          if (provider.errorMessage != null && provider.compras.isEmpty) {
            return EmptyState(
              icono: Icons.error_outline,
              titulo: 'Error al consultar tus compras',
              mensaje: provider.errorMessage!,
              textoBoton: 'Reintentar',
              onReintentar: () => provider.cargarCompras(),
            );
          }

          if (provider.compras.isEmpty) {
            return EmptyState(
              icono: Icons.shopping_bag_outlined,
              titulo: 'Aún no tenés compras online',
              mensaje:
                  'Explorá nuestras colecciones de prendas y realizá tu primer pedido desde la tienda.',
              textoBoton: 'Ir al Catálogo',
              onReintentar: () => context.go('/'),
            );
          }

          return RefreshIndicator(
            onRefresh: () => provider.cargarCompras(),
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 10),
              itemCount: provider.compras.length,
              itemBuilder: (context, index) {
                final venta = provider.compras[index];
                return VentaTile(venta: venta);
              },
            ),
          );
        },
      ),
    );
  }
}
