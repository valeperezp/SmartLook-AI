import 'package:flutter/foundation.dart';

import '../../../core/network/api_exceptions.dart';
import '../../../core/network/dio_client.dart';
import '../data/suscripcion_stock_dao.dart';

/// El servidor rechazó la petición (4xx): reintentar no va a funcionar.
class RechazoServidor implements Exception {
  const RechazoServidor(this.codigo, this.mensaje);

  final int codigo;
  final String mensaje;

  @override
  String toString() => 'Rechazo del servidor ($codigo): $mensaje';
}

/// Las tres llamadas del backend que usan los avisos de stock (CU16). Se puede reemplazar en pruebas.
abstract class ApiSuscripciones {
  /// `POST /suscripciones` con la suscripción; devuelve la que guardó el servidor.
  Future<Map<String, dynamic>> crear(Map<String, dynamic> cuerpo);

  /// `GET /suscripciones/mis-notificaciones`: las prendas que el cliente esperaba y ya llegaron.
  Future<List<Map<String, dynamic>>> misNotificaciones();

  /// `POST /suscripciones/marcar-vistas`.
  Future<void> marcarVistas();
}

class ApiSuscripcionesDio implements ApiSuscripciones {
  RechazoServidor? _rechazo(Object e) {
    final codigo = (e as dynamic).response?.statusCode as int?;
    if (codigo != null && codigo >= 400 && codigo < 500) {
      final error = (e as dynamic).error;
      return RechazoServidor(codigo, error is ApiException ? error.message : 'El servidor rechazó la petición');
    }
    return null;
  }

  @override
  Future<Map<String, dynamic>> crear(Map<String, dynamic> cuerpo) async {
    try {
      final r = await DioClient().post<Map<String, dynamic>>('/suscripciones', data: cuerpo);
      return r.data ?? const {};
    } catch (e) {
      throw _rechazo(e) ?? e;
    }
  }

  @override
  Future<List<Map<String, dynamic>>> misNotificaciones() async {
    final r = await DioClient().get<List<dynamic>>('/suscripciones/mis-notificaciones');
    return [for (final x in (r.data ?? const [])) Map<String, dynamic>.from(x as Map)];
  }

  @override
  Future<void> marcarVistas() async {
    await DioClient().post<dynamic>('/suscripciones/marcar-vistas', data: const {});
  }
}

/// Qué pasó en una pasada de sincronización de avisos.
class ResultadoSuscripcionesSync {
  const ResultadoSuscripcionesSync({this.enviadas = 0, this.rechazadas = 0, this.nuevosAvisos = 0, this.sinRed = false});

  final int enviadas;
  final int rechazadas;

  /// Avisos "ya llegó" que el cliente todavía no vio.
  final int nuevosAvisos;

  /// No se pudo hablar con el servidor: lo guardado en el dispositivo sigue pendiente.
  final bool sinRed;
}

/// Sincroniza los avisos "Avísame cuando llegue" con el servidor (CU16).
///
/// La tabla local `suscripciones_stock` hace de cola de envío: lo que se pidió sin conexión sigue 'pendiente' hasta que el servidor
/// lo recibe (con su `id` como uuid, así que reenviar no duplica). Después se leen los avisos del servidor y los que ya llegaron
/// (también los pedidos desde la web) se marcan 'notificado' en el dispositivo para mostrar la campana y el SnackBar.
class SuscripcionesRemotas {
  SuscripcionesRemotas({ApiSuscripciones? api, SuscripcionStockDao? dao}) : _api = api ?? ApiSuscripcionesDio(), _dao = dao ?? SuscripcionStockDao();

  final ApiSuscripciones _api;
  final SuscripcionStockDao _dao;

  Future<ResultadoSuscripcionesSync> sincronizar(int clienteId) async {
    var enviadas = 0, rechazadas = 0, nuevos = 0;
    try {
      for (final p in await _dao.obtenerPorEnviar(clienteId)) {
        final id = p['id'] as String;
        try {
          final r = await _api.crear({
            'uuid': id,
            'producto_id': p['producto_id'],
            'talla_id': p['talla_id'],
            'color_id': p['color_id'],
            'sucursal_id': p['sucursal_id'],
          });
          await _dao.marcarEnviada(id, r['id'] as int);
          enviadas++;
          if (r['estado'] == 'notificado') nuevos += await _dao.aplicarNotificacionesDelServidor(clienteId, [r]);
        } on RechazoServidor catch (e) {
          debugPrint('[SuscripcionesRemotas] El servidor rechazó el aviso $id: $e');
          await _dao.marcarRechazadaPorServidor(id);
          rechazadas++;
        }
      }
      nuevos += await _dao.aplicarNotificacionesDelServidor(clienteId, await _api.misNotificaciones());
    } catch (e) {
      // sin red, timeout o servidor caído: lo pendiente sigue pendiente y se reintenta luego
      debugPrint('[SuscripcionesRemotas] No se pudo sincronizar los avisos: $e');
      return ResultadoSuscripcionesSync(enviadas: enviadas, rechazadas: rechazadas, nuevosAvisos: nuevos, sinRed: true);
    }
    return ResultadoSuscripcionesSync(enviadas: enviadas, rechazadas: rechazadas, nuevosAvisos: nuevos);
  }

  /// El cliente ya vio sus avisos: se avisa al servidor (si no hay red, se ignora).
  Future<void> marcarVistas() async {
    try {
      await _api.marcarVistas();
    } catch (e) {
      debugPrint('[SuscripcionesRemotas] No se pudo marcar los avisos como vistos en el servidor: $e');
    }
  }
}
