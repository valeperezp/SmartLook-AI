import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/conectividad_provider.dart';

/// Franja pequeña que aparece solo cuando el dispositivo no tiene red.
class BannerOffline extends StatelessWidget {
  const BannerOffline({super.key});

  @override
  Widget build(BuildContext context) {
    final online = context.select<ConectividadProvider, bool>((c) => c.online);
    if (online) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      color: Colors.orange.shade800,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: const Row(
        children: [
          Icon(Icons.cloud_off, size: 16, color: Colors.white),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Modo Offline Activo - Los datos se guardarán localmente',
              style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
