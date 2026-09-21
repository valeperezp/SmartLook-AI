import 'package:flutter/material.dart';
import '../../../../core/models/sucursal.dart';
import '../../../../core/theme/app_theme.dart';

class SucursalTile extends StatelessWidget {
  final Sucursal sucursal;
  final VoidCallback onEditar;
  final VoidCallback onDesactivar;

  const SucursalTile({
    super.key,
    required this.sucursal,
    required this.onEditar,
    required this.onDesactivar,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppTheme.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        side: BorderSide(
          color: sucursal.activa ? AppTheme.border : Colors.grey.shade300,
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Fila superior: Ícono, Nombre y Botón Editar
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: sucursal.activa
                      ? Colors.indigo.shade50
                      : Colors.grey.shade200,
                  child: Icon(
                    Icons.storefront,
                    color: sucursal.activa
                        ? Colors.indigo.shade800
                        : Colors.grey.shade600,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sucursal.nombre,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: sucursal.activa
                              ? AppTheme.textPrimary
                              : Colors.grey.shade600,
                        ),
                      ),
                      if (sucursal.ciudad != null &&
                          sucursal.ciudad!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          sucursal.ciudad!,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  color: AppTheme.primary,
                  tooltip: 'Editar',
                  onPressed: onEditar,
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Dirección
            Row(
              children: [
                Icon(Icons.location_on_outlined,
                    size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    sucursal.direccion.isNotEmpty
                        ? sucursal.direccion
                        : 'Sin dirección especificada',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
              ],
            ),

            // Teléfono (si existe)
            if (sucursal.telefono != null && sucursal.telefono!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.phone_outlined,
                      size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 6),
                  Text(
                    sucursal.telefono!,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ],
            const Divider(height: 20),

            // Estado y acción desactivar
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Chip(
                  label: Text(
                    sucursal.activa ? 'Operativa' : 'Inactiva',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: sucursal.activa
                          ? Colors.teal.shade800
                          : Colors.grey.shade700,
                    ),
                  ),
                  backgroundColor: sucursal.activa
                      ? Colors.teal.shade50
                      : Colors.grey.shade200,
                  side: BorderSide.none,
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
                if (sucursal.activa)
                  TextButton.icon(
                    onPressed: onDesactivar,
                    icon: Icon(
                      Icons.delete_outline,
                      size: 18,
                      color: Colors.red.shade700,
                    ),
                    label: Text(
                      'Desactivar',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.red.shade700,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
