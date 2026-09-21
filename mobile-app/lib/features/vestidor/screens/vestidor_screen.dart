import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../../core/services/catalogo_service.dart';
import '../../catalogo/widgets/detalle_producto_modal.dart';
import '../models/producto_ar.dart';
import '../providers/vestidor_provider.dart';

class VestidorScreen extends StatefulWidget {
  final int? productoId;

  const VestidorScreen({
    super.key,
    this.productoId,
  });

  @override
  State<VestidorScreen> createState() => _VestidorScreenState();
}

class _VestidorScreenState extends State<VestidorScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context
          .read<VestidorProvider>()
          .cargarProductosCatalogo(seleccionarId: widget.productoId);
    });
  }

  void _abrirModalDetalle(BuildContext context, ProductoAr prod) async {
    final catService = CatalogoService();
    try {
      final productoCompleto =
          await catService.obtenerProducto(prod.productoId);
      if (!context.mounted) return;
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => DetalleProductoModal(
          producto: productoCompleto,
          service: catService,
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir el detalle del producto.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<VestidorProvider>();
    final primaryColor = Colors.indigo.shade800;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Vestidor Virtual con IA',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: primaryColor,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/');
            }
          },
        ),
        actions: [
          if (provider.fotoUsuarioBytes != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Reiniciar prueba',
              onPressed: () => provider.limpiarFoto(),
            ),
        ],
      ),
      body: provider.cargando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => provider.cargarProductosCatalogo(
                seleccionarId: provider.productoActual?.productoId,
              ),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 1. Selector horizontal de prendas
                        _buildSeccionPrendas(provider),
                        const SizedBox(height: 18),

                        // Mensajes de error o info
                        if (provider.errorMessage != null)
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade50,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.amber.shade300),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.info_outline,
                                    color: Colors.amber.shade900, size: 22),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    provider.errorMessage!,
                                    style: const TextStyle(
                                      color: Color(0xFF78350F),
                                      fontSize: 13,
                                      height: 1.3,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                        // 2. Área principal del vestidor
                        _buildAreaVestidor(provider),
                        const SizedBox(height: 20),

                        // 3. Acciones de compra / reserva de la prenda seleccionada
                        if (provider.productoActual != null)
                          _buildCardAccionesPrenda(provider),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildSeccionPrendas(VestidorProvider provider) {
    if (provider.productos.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '1. Elegí la prenda para probarte:',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 100,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: provider.productos.length,
            separatorBuilder: (context, index) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final prod = provider.productos[index];
              final isSelected =
                  provider.productoActual?.productoId == prod.productoId;

              return InkWell(
                onTap: () => provider.seleccionarProducto(prod),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 90,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.indigo.shade50 : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? Colors.indigo.shade700
                          : Colors.grey.shade300,
                      width: isSelected ? 2 : 1,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: Colors.indigo.shade100,
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            )
                          ]
                        : null,
                  ),
                  child: Column(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: prod.imagenUrl != null &&
                                  prod.imagenUrl!.isNotEmpty
                              ? Image.network(
                                  prod.imagenUrl!,
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  errorBuilder: (context, error, stackTrace) =>
                                      Icon(
                                    Icons.checkroom,
                                    color: Colors.indigo.shade400,
                                    size: 32,
                                  ),
                                )
                              : Icon(
                                  Icons.checkroom,
                                  color: Colors.indigo.shade400,
                                  size: 32,
                                ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        prod.nombre,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected
                              ? Colors.indigo.shade900
                              : Colors.black87,
                        ),
                      ),
                      Text(
                        '\$${prod.precio.toStringAsFixed(0)}',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Colors.indigo.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAreaVestidor(VestidorProvider provider) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Container(
        width: double.infinity,
        color: Colors.white,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Si ya hay resultado de IA
            if (provider.resultadoPrueba != null) ...[
              _buildResultadoIA(provider),
            ] else if (provider.fotoUsuarioBytes != null) ...[
              // Foto tomada, lista para procesar
              _buildFotoPreparada(provider),
            ] else ...[
              // Estado inicial: Invitar a tomarse una foto
              _buildCapturaInicial(provider),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCapturaInicial(VestidorProvider provider) {
    return Column(
      children: [
        const SizedBox(height: 12),
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: Colors.indigo.shade50,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.camera_alt_outlined,
              size: 40, color: Colors.indigo.shade700),
        ),
        const SizedBox(height: 16),
        const Text(
          '2. Subí o tomate una foto',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Para que la Inteligencia Artificial genere cómo te quedaría "${provider.productoActual?.nombre ?? 'la prenda'}", tomate una foto de cuerpo completo o medio cuerpo.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.4),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () => provider.capturarFoto(ImageSource.camera),
                icon: const Icon(Icons.camera_alt),
                label: const Text('Tomar Foto'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.indigo.shade700,
                  side: BorderSide(color: Colors.indigo.shade700),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () => provider.capturarFoto(ImageSource.gallery),
                icon: const Icon(Icons.photo_library),
                label: const Text('Galería'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildFotoPreparada(VestidorProvider provider) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Foto lista para probar',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            TextButton.icon(
              onPressed: () => provider.limpiarFoto(),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Cambiar'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 260,
            width: double.infinity,
            child: Image.memory(
              provider.fotoUsuarioBytes!,
              fit: BoxFit.cover,
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo.shade700,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: provider.procesandoFoto
                ? null
                : () => provider.generarPruebaVirtual(),
            icon: provider.procesandoFoto
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.auto_awesome),
            label: Text(
              provider.procesandoFoto
                  ? 'Generando con IA...'
                  : 'Probar Prenda con IA',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResultadoIA(VestidorProvider provider) {
    final imageBytes = base64Decode(provider.resultadoPrueba!.imagenBase64);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome,
                    color: Colors.indigo.shade700, size: 20),
                const SizedBox(width: 6),
                const Text(
                  'Resultado Virtual con IA',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.green.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Fotorrealista',
                style: TextStyle(
                  color: Colors.green.shade900,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 320,
            width: double.infinity,
            child: Image.memory(
              imageBytes,
              fit: BoxFit.cover,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.indigo.shade700,
                  side: BorderSide(color: Colors.indigo.shade700),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () => provider.limpiarFoto(),
                icon: const Icon(Icons.camera_alt),
                label: const Text('Probar otra foto'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCardAccionesPrenda(VestidorProvider provider) {
    final prod = provider.productoActual!;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: prod.imagenUrl != null && prod.imagenUrl!.isNotEmpty
                  ? Image.network(
                      prod.imagenUrl!,
                      width: 60,
                      height: 60,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        width: 60,
                        height: 60,
                        color: Colors.grey.shade100,
                        child: const Icon(Icons.checkroom),
                      ),
                    )
                  : Container(
                      width: 60,
                      height: 60,
                      color: Colors.grey.shade100,
                      child: const Icon(Icons.checkroom),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    prod.nombre,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '\$${prod.precio.toStringAsFixed(2)}',
                    style: TextStyle(
                      color: Colors.indigo.shade700,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade700,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () => _abrirModalDetalle(context, prod),
              icon: const Icon(Icons.shopping_bag_outlined, size: 18),
              label: const Text('Comprar'),
            ),
          ],
        ),
      ),
    );
  }
}
