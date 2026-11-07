import 'package:flutter/foundation.dart';

import '../../../core/services/fidelizacion_service.dart';
import '../data/puntos_dao.dart';

/// Saldo de puntos de un cliente que el cajero puede canjear (CU17).
///
/// Con red se pregunta al servidor (el saldo real, incluidos los puntos ganados en otras compras) y se alinea el saldo
/// local con él; sin red se usa el saldo guardado en este dispositivo.
class SaldoPuntosCliente {
  SaldoPuntosCliente({FidelizacionService? servicio, PuntosDao? dao})
      : _servicio = servicio ?? FidelizacionService(),
        _dao = dao ?? PuntosDao();

  final FidelizacionService _servicio;
  final PuntosDao _dao;

  Future<int> disponible(int clienteId) async {
    try {
      final p = await _servicio.puntosDeCliente(clienteId);
      return await _dao.reconciliarSaldo(clienteId, p.saldo);
    } catch (e) {
      debugPrint('[SaldoPuntosCliente] Sin saldo del servidor para $clienteId ($e): se usa el saldo local.');
      return _dao.obtenerSaldo(clienteId);
    }
  }
}
