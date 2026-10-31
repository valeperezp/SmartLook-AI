import 'package:flutter/foundation.dart';

import '../../../core/database/app_database.dart';
import '../data/puntos_dao.dart';

/// Un movimiento de puntos listo para mostrar.
class MovimientoPuntos {
  const MovimientoPuntos({required this.tipo, required this.cantidad, required this.fecha, required this.sincronizado});

  /// 'ganado', 'perdido' o 'canjeado'.
  final String tipo;
  final int cantidad;
  final DateTime fecha;
  final bool sincronizado;

  /// Con signo: +10 si se ganaron, -4 si se perdieron.
  int get delta => tipo == 'ganado' ? cantidad : -cantidad;

  factory MovimientoPuntos.fromMap(Map<String, dynamic> m) => MovimientoPuntos(
        tipo: m['tipo'] as String,
        cantidad: m['cantidad'] as int,
        fecha: DateTime.parse(m['fecha'] as String).toLocal(),
        sincronizado: m['estado_sync'] == 'sincronizado',
      );
}

/// Saldo y movimientos de puntos de fidelización del cliente (CU17).
class PuntosProvider extends ChangeNotifier {
  PuntosProvider({PuntosDao? dao}) : _dao = dao ?? PuntosDao();

  final PuntosDao _dao;

  int _saldo = 0;
  List<MovimientoPuntos> _movimientos = const [];
  bool _cargando = false;
  String? _error;

  int get saldo => _saldo;
  List<MovimientoPuntos> get movimientos => _movimientos;
  bool get cargando => _cargando;
  String? get error => _error;
  bool get soportado => AppDatabase.soportado;

  Future<void> cargar(int clienteId) async {
    if (!soportado) {
      _error = 'Los puntos offline no están disponibles en web.';
      notifyListeners();
      return;
    }
    _cargando = true;
    notifyListeners();
    try {
      _saldo = await _dao.obtenerSaldo(clienteId);
      _movimientos = (await _dao.listarMovimientos(clienteId)).map(MovimientoPuntos.fromMap).toList(growable: false);
      _error = null;
    } catch (e, st) {
      debugPrint('[PuntosProvider] Error al cargar los puntos: $e\n$st');
      _error = 'No se pudieron leer los puntos.';
    } finally {
      _cargando = false;
      notifyListeners();
    }
  }
}
