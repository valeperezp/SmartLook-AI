import 'dart:math';

import 'package:smartlook_mobile/features/offline/services/sync_service.dart';

/// Servidor FALSO solo para pruebas (la app ya no simula nada: envía `POST /sync/operaciones`).
///
/// Cada operación/devolución sale `ok` (con un id falso) o `conflict` según [sorteo] y [probabilidadConflicto]
/// (por defecto ~20 % de conflictos). Los cierres de caja y los movimientos de puntos se aceptan siempre.
EnviarLote servidorSimulado({double Function()? sorteo, double probabilidadConflicto = 0.2}) {
  final tirar = sorteo ?? Random().nextDouble;
  var idServidor = 900000000; // ids claramente falsos, para no confundirlos con los reales
  return (Map<String, dynamic> lote) async {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    return {
      'resultados': [
        for (final cierre in (lote['cierres_caja'] as List? ?? const []))
          {'uuid': (cierre as Map)['uuid'], 'status': 'ok', 'id_servidor': idServidor++},
        for (final mov in (lote['movimientos_puntos'] as List? ?? const []))
          {'uuid': (mov as Map)['uuid'], 'status': 'ok'},
        for (final dev in (lote['devoluciones'] as List? ?? const []))
          if (tirar() < probabilidadConflicto)
            {'uuid': (dev as Map)['uuid'], 'status': 'conflict', 'message': 'Stock insuficiente'}
          else
            {'uuid': (dev as Map)['uuid'], 'status': 'ok', 'id_servidor': idServidor++},
        for (final op in (lote['operaciones'] as List? ?? const []))
          if (tirar() < probabilidadConflicto)
            {'uuid': (op as Map)['uuid'], 'status': 'conflict', 'message': 'Stock insuficiente'}
          else
            {'uuid': (op as Map)['uuid'], 'status': 'ok', 'id_servidor': idServidor++},
      ],
    };
  };
}
