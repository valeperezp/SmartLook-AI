import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../../../core/database/app_database.dart';

/// Estado de la red para mostrar el aviso "Modo Offline" en la UI.
///
/// Empieza asumiendo que hay red (no muestra el aviso por error mientras consulta). Igual que en
/// `SyncService`, "hay red" significa que existe una interfaz activa, no que llegue a internet.
class ConectividadProvider extends ChangeNotifier {
  ConectividadProvider({Stream<List<ConnectivityResult>>? cambios, Future<List<ConnectivityResult>> Function()? consultar}) {
    if (!AppDatabase.soportado) return; // el módulo offline no existe en web
    _suscripcion = (cambios ?? Connectivity().onConnectivityChanged).listen(
      _actualizar,
      onError: (Object e, StackTrace st) => debugPrint('[ConectividadProvider] Error en el stream: $e\n$st'),
    );
    _consultarEstadoInicial(consultar ?? Connectivity().checkConnectivity);
  }

  StreamSubscription<List<ConnectivityResult>>? _suscripcion;
  bool _online = true;
  bool _recibioEvento = false;

  bool get online => _online;

  Future<void> _consultarEstadoInicial(Future<List<ConnectivityResult>> Function() consultar) async {
    try {
      final resultados = await consultar();
      if (!_recibioEvento) _actualizar(resultados); // un evento más reciente tiene prioridad
    } catch (e) {
      debugPrint('[ConectividadProvider] No se pudo leer el estado inicial de la red: $e');
    }
  }

  void _actualizar(List<ConnectivityResult> resultados) {
    _recibioEvento = true;
    final online = resultados.any((r) => r != ConnectivityResult.none);
    if (online == _online) return;
    _online = online;
    notifyListeners();
  }

  @override
  void dispose() {
    _suscripcion?.cancel();
    super.dispose();
  }
}
