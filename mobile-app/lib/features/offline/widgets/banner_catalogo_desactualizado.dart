import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/catalogo_offline_provider.dart';

/// Aviso ámbar sobre la lista del catálogo offline: aparece solo si lo guardado tiene más de 24 horas (CU8).
class BannerCatalogoDesactualizado extends StatelessWidget {
  const BannerCatalogoDesactualizado({super.key});

  /// "hace 5 horas" / "hace 2 días" / "hace 1 hora" (para menos de 48 h se cuenta en horas).
  static String antiguedadTexto(Duration d) {
    if (d.inHours < 48) {
      final h = d.inHours < 1 ? 1 : d.inHours;
      return 'hace $h ${h == 1 ? "hora" : "horas"}';
    }
    final dias = d.inDays;
    return 'hace $dias ${dias == 1 ? "día" : "días"}';
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CatalogoOfflineProvider>();
    if (!provider.desactualizado) return const SizedBox.shrink();
    final antiguedad = provider.antiguedad;

    return Container(
      key: const Key('banner_catalogo_desactualizado'),
      width: double.infinity,
      color: Colors.amber.shade100,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.update_disabled, size: 20, color: Colors.amber.shade900),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Información desactualizada',
                  style: TextStyle(color: Colors.amber.shade900, fontWeight: FontWeight.w700),
                ),
                Text(
                  'La información puede estar desactualizada. Conéctate a internet para actualizar.',
                  style: TextStyle(color: Colors.amber.shade900),
                ),
                if (antiguedad != null)
                  Text(
                    'Última actualización: ${antiguedadTexto(antiguedad)}.',
                    style: TextStyle(color: Colors.amber.shade900, fontSize: 12),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
