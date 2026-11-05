import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Las hojas inferiores (modales) se pintan sobre fondo blanco aunque la app sea oscura.
/// Este tema claro hace que sus campos, textos y botones se lean bien sobre ese fondo.
class HojaClara extends StatelessWidget {
  const HojaClara({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(seedColor: AppTheme.primaryDark, brightness: Brightness.light),
    );
    // Material transparente: aplica el estilo de texto claro (si no, el texto sin color hereda el del tema oscuro)
    return Theme(data: base, child: Material(type: MaterialType.transparency, child: child));
  }
}

/// Abre una hoja inferior blanca con tema claro: por encima de la barra de navegación, bajo la barra de estado
/// y con textos y campos legibles aunque la app sea oscura.
Future<T?> mostrarHojaClara<T>(BuildContext context, WidgetBuilder builder) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => HojaClara(child: builder(ctx)),
  );
}

/// Como [mostrarHojaClara], pero para contenidos que no traen su propio fondo: los pone sobre una hoja blanca
/// con las esquinas superiores redondeadas.
Future<T?> mostrarHojaClaraConFondo<T>(BuildContext context, WidgetBuilder builder) {
  return mostrarHojaClara<T>(
    context,
    (ctx) => Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: builder(ctx),
    ),
  );
}
