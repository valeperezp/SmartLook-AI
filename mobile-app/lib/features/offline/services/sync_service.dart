import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/schema.dart';
import '../../../core/network/dio_client.dart';
import '../data/devolucion_dao.dart';
import '../data/puntos_dao.dart';
import '../data/qr_devolucion_dao.dart';
import '../data/sync_queue_dao.dart';
import '../data/turno_caja_dao.dart';

/// Resultado de una pasada de sincronización.
class ResultadoSync {
  const ResultadoSync({
    this.sincronizadas = 0,
    this.rechazadas = 0,
    this.fallidas = 0,
    this.sinRed = false,
    this.yaEnCurso = false,
    this.sesionExpirada = false,
    this.enEspera = 0,
    this.motivoEspera,
    this.enConflicto = 0,
  });

  final int sincronizadas;
  final int rechazadas;

  /// Quedaron 'pendiente' para reintentar (error de red o respuesta no entendida).
  final int fallidas;
  final bool sinRed;
  final bool yaEnCurso;

  /// El servidor respondió 401: nada se perdió (todo sigue pendiente) pero hay que volver a iniciar sesión.
  final bool sesionExpirada;

  /// El servidor respondió `pendiente`: todavía no puede decidir (p. ej. falta sincronizar la venta original). No es un
  /// error ni un rechazo: la operación sigue 'pendiente' en SQLite y se reenvía en la próxima sincronización.
  final int enEspera;

  /// Mensaje del servidor de la primera operación en espera (p. ej. "La venta original aún no está sincronizada").
  final String? motivoEspera;

  /// CU13: el servidor guardó la venta pero sin stock suficiente (`en_conflicto`). Quedó marcada así en SQLite, SIN devolver el
  /// stock local (la venta ya se hizo); un encargado la resuelve desde la web.
  final int enConflicto;

  int get total => sincronizadas + rechazadas + fallidas + enEspera + enConflicto;

  String get resumen {
    if (yaEnCurso) return 'Ya hay una sincronización en curso.';
    if (sinRed) return 'Sin conexión: no se sincronizó nada.';
    if (sesionExpirada) return 'Sesión expirada: vuelve a iniciar sesión. Tus operaciones siguen guardadas en el dispositivo.';
    if (total == 0) return 'No hay operaciones pendientes.';
    final partes = <String>[
      if (sincronizadas > 0) '$sincronizadas ${sincronizadas == 1 ? "sincronizada" : "sincronizadas"}',
      if (rechazadas > 0) '$rechazadas ${rechazadas == 1 ? "rechazada" : "rechazadas"}',
      if (enConflicto > 0) '$enConflicto en conflicto (la resuelve el encargado)',
      if (fallidas > 0) '$fallidas ${fallidas == 1 ? "pendiente de reintentar" : "pendientes de reintentar"}',
      if (enEspera > 0) '$enEspera en espera${motivoEspera == null ? "" : " (${motivoEspera!})"}',
    ];
    return partes.join(', ');
  }
}

/// Envío al backend: recibe el lote y devuelve `{"resultados": [{uuid, status, id_servidor?, message?}]}`.
typedef EnviarLote = Future<Map<String, dynamic>> Function(Map<String, dynamic> lote);

/// El servidor respondió 401: la sesión venció. Las operaciones NO se pierden, quedan pendientes.
class SesionExpiradaSync implements Exception {
  const SesionExpiradaSync();

  @override
  String toString() => 'Sesión expirada (401).';
}

/// Lee la cola de SQLite, arma el lote JSON (con el uuid local de cada operación, que sirve de clave de
/// idempotencia) y lo envía con `POST /sync/operaciones` (Bearer token del [DioClient]).
///
/// Respuesta esperada (200): `{"resultados": [{uuid, status: ok|conflict, id_servidor?, message?}]}`; también se
/// acepta un `{"status": "ok"|"conflict"}` para todo el lote. Con 401 el lote queda pendiente y se detiene la
/// sincronización ([ResultadoSync.sesionExpirada]); con error de red, timeout, 404 o 5xx todo queda pendiente
/// para reintentar. En pruebas se inyecta [enviar] o un [Dio] falso.
class SyncService {
  SyncService({
    SyncQueueDao? colaDao,
    TurnoCajaDao? turnoDao,
    DevolucionDao? devolucionDao,
    PuntosDao? puntosDao,
    QrDevolucionDao? qrDao,
    Future<bool> Function()? hayRed,
    EnviarLote? enviar,
    Dio? dio,
    this.cambiosDeRed,
    this.esperaTrasReconexion = const Duration(seconds: 3),
    this.intervaloMinimoAuto = const Duration(seconds: 15),
    this.sincronizarAlIniciar = true,
  })  : _colaDao = colaDao ?? SyncQueueDao(),
        _turnoDao = turnoDao ?? TurnoCajaDao(),
        _devolucionDao = devolucionDao ?? DevolucionDao(),
        _puntosDao = puntosDao ?? PuntosDao(),
        _qrDao = qrDao ?? QrDevolucionDao(),
        _hayRed = hayRed ?? _hayRedPorDefecto,
        _dioInyectado = dio {
    _enviar = enviar ?? _enviarPorHttp;
  }

  final SyncQueueDao _colaDao;
  final TurnoCajaDao _turnoDao;
  final DevolucionDao _devolucionDao;
  final PuntosDao _puntosDao;
  final QrDevolucionDao _qrDao;
  final Future<bool> Function() _hayRed;
  final Dio? _dioInyectado;
  late final Dio _dio = _dioInyectado ?? DioClient().dio;
  final Stream<List<ConnectivityResult>>? cambiosDeRed;

  /// Tras volver la red se espera este tiempo SIN nuevos cambios antes de sincronizar (un wifi que
  /// parpadea reinicia la espera en vez de disparar un envío por cada parpadeo).
  final Duration esperaTrasReconexion;

  /// Separación mínima entre dos sincronizaciones automáticas consecutivas.
  final Duration intervaloMinimoAuto;

  /// Si la app arranca con red, intenta enviar lo que quedó pendiente de la sesión anterior.
  final bool sincronizarAlIniciar;

  late final EnviarLote _enviar;
  StreamSubscription<List<ConnectivityResult>>? _suscripcion;
  Timer? _temporizador;
  bool? _hayRedAntes;
  DateTime? _ultimaAuto;
  bool _liberado = false;
  final _resultadosAuto = StreamController<ResultadoSync>.broadcast();

  /// Resultado de cada sincronización AUTOMÁTICA que movió algo (para refrescar pantallas y avisar).
  Stream<ResultadoSync> get alSincronizarAutomaticamente => _resultadosAuto.stream;
  bool _enCurso = false;

  /// connectivity_plus solo sabe si hay una interfaz de red activa (wifi/datos), no si llega a internet:
  /// por eso un fallo de envío igualmente deja la operación pendiente.
  static Future<bool> _hayRedPorDefecto() async {
    final resultados = await Connectivity().checkConnectivity();
    return resultados.any((r) => r != ConnectivityResult.none);
  }

  static bool hayRedEn(List<ConnectivityResult> resultados) =>
      resultados.any((r) => r != ConnectivityResult.none);

  /// Empieza a escuchar los cambios de conectividad: al pasar de sin red a con red (wifi/datos) programa una
  /// sincronización automática. Hay que llamar a [dispose] para cancelar la suscripción.
  Future<void> iniciarEscucha() async {
    if (_suscripcion != null || _liberado || !AppDatabase.soportado) return;
    _suscripcion = (cambiosDeRed ?? Connectivity().onConnectivityChanged).listen(
      _alCambiarLaRed,
      onError: (Object e, StackTrace st) => debugPrint('[SyncService] Error en el stream de conectividad: $e\n$st'),
    );
    try {
      _hayRedAntes = await _hayRed();
    } catch (e) {
      debugPrint('[SyncService] No se pudo leer el estado inicial de la red: $e');
    }
    if (_hayRedAntes == true && sincronizarAlIniciar) _programarSincronizacion();
  }

  void _alCambiarLaRed(List<ConnectivityResult> resultados) {
    final hayRed = hayRedEn(resultados);
    final antes = _hayRedAntes;
    _hayRedAntes = hayRed;
    if (!hayRed) {
      _temporizador?.cancel(); // se cayó otra vez antes de que se cumpliera la espera
      _temporizador = null;
    } else if (antes != true) {
      _programarSincronizacion(); // pasó de sin red (o estado desconocido) a con red
    }
  }

  void _programarSincronizacion() {
    _temporizador?.cancel();
    var espera = esperaTrasReconexion;
    final ultima = _ultimaAuto;
    if (ultima != null) {
      final falta = intervaloMinimoAuto - DateTime.now().difference(ultima);
      if (falta > espera) espera = falta;
    }
    _temporizador = Timer(espera, _sincronizacionAutomatica);
  }

  Future<void> _sincronizacionAutomatica() async {
    _temporizador = null;
    if (_liberado) return;
    _ultimaAuto = DateTime.now();
    try {
      final r = await sincronizarPendientes();
      if (_liberado) return;
      if (r.total > 0 || r.sesionExpirada) _resultadosAuto.add(r);
    } catch (e, st) {
      debugPrint('[SyncService] Falló la sincronización automática: $e\n$st');
    }
  }

  /// Cancela la suscripción a la red y los temporizadores pendientes.
  Future<void> dispose() async {
    _liberado = true;
    _temporizador?.cancel();
    _temporizador = null;
    await _suscripcion?.cancel();
    _suscripcion = null;
    await _resultadosAuto.close();
  }

  Future<ResultadoSync> sincronizarPendientes() async {
    if (_enCurso) return const ResultadoSync(yaEnCurso: true);
    _enCurso = true;
    try {
      if (!await _hayRed()) {
        debugPrint('[SyncService] Sin red: no se intenta sincronizar.');
        return const ResultadoSync(sinRed: true);
      }

      await _colaDao.liberarOperacionesEnProceso();
      final pendientes = await _colaDao.obtenerOperacionesPendientes();
      if (pendientes.isEmpty) return const ResultadoSync();

      // Orden: ventas/reservas, cambios/devoluciones (necesitan su venta ya en el servidor), puntos (necesitan su
      // venta o devolución), los cierres de caja (necesitan todo lo de su turno) y los QR de reembolso (no dependen de nada).
      const tiposAparte = {
        Schema.tipoCierreCaja,
        Schema.tipoOperacionDevolucion,
        Schema.tipoPuntosOtorgados,
        Schema.tipoPuntosRestados,
        Schema.tipoSubirQrDevolucion,
      };
      final operaciones = [for (final p in pendientes) if (!tiposAparte.contains(p['tipo_operacion'])) p];
      final devoluciones = [for (final p in pendientes) if (p['tipo_operacion'] == Schema.tipoOperacionDevolucion) p];
      final puntos = [
        for (final p in pendientes)
          if (p['tipo_operacion'] == Schema.tipoPuntosOtorgados || p['tipo_operacion'] == Schema.tipoPuntosRestados) p,
      ];
      final cierres = [for (final p in pendientes) if (p['tipo_operacion'] == Schema.tipoCierreCaja) p];
      final qrs = [for (final p in pendientes) if (p['tipo_operacion'] == Schema.tipoSubirQrDevolucion) p];

      final etapas = <Future<ResultadoSync> Function()>[
        if (operaciones.isNotEmpty) () => _enviarOperaciones(operaciones),
        if (devoluciones.isNotEmpty) () => _enviarDevoluciones(devoluciones),
        if (puntos.isNotEmpty) () => _enviarPuntos(puntos),
        if (cierres.isNotEmpty) () => _enviarCierres(cierres),
        if (qrs.isNotEmpty) () => _enviarQrs(qrs),
      ];
      final resultados = <ResultadoSync>[];
      var sesionExpirada = false;
      for (final etapa in etapas) {
        final r = await etapa();
        resultados.add(r);
        if (r.sesionExpirada) {
          // 401: no tiene sentido seguir con las demás etapas, el token ya no vale. Lo pendiente queda pendiente.
          sesionExpirada = true;
          break;
        }
      }
      return ResultadoSync(
        sincronizadas: resultados.fold(0, (s, r) => s + r.sincronizadas),
        rechazadas: resultados.fold(0, (s, r) => s + r.rechazadas),
        fallidas: resultados.fold(0, (s, r) => s + r.fallidas),
        sesionExpirada: sesionExpirada,
        enEspera: resultados.fold(0, (s, r) => s + r.enEspera),
        enConflicto: resultados.fold(0, (s, r) => s + r.enConflicto),
        motivoEspera: resultados.map((r) => r.motivoEspera).whereType<String>().firstOrNull,
      );
    } finally {
      _enCurso = false;
    }
  }

  Future<ResultadoSync> _enviarOperaciones(List<Map<String, dynamic>> pendientes) async {
    final lote = await _armarLote(pendientes);
    await _colaDao.marcarEnProceso([for (final p in pendientes) p['id'] as String]);

    Map<String, dynamic> respuesta;
    try {
      respuesta = await _enviar(lote);
    } catch (e, st) {
      debugPrint('[SyncService] Falló el envío del lote: $e\n$st');
      for (final p in pendientes) {
        await _colaDao.devolverAPendiente(p['id'] as String, 'Error de envío: $e');
      }
      return ResultadoSync(fallidas: pendientes.length, sesionExpirada: e is SesionExpiradaSync);
    }

    return _procesarRespuesta(pendientes, respuesta);
  }

  /// Envía los cambios/devoluciones cuya venta original ya está en el servidor. Si la venta sigue pendiente la
  /// devolución espera (sin contarse como fallo); si el servidor la rechazó, la devolución se rechaza también y se
  /// deshace su efecto en el stock local.
  Future<ResultadoSync> _enviarDevoluciones(List<Map<String, dynamic>> pendientes) async {
    var rechazadas = 0, fallidas = 0;
    final listas = <Map<String, dynamic>>[];
    for (final p in pendientes) {
      final id = p['devolucion_id'] as String;
      try {
        final d = await _devolucionDao.obtenerParaSincronizar(id);
        if (d == null) throw StateError('la devolución $id no existe');
        switch (d['estado_venta']) {
          case 'sincronizada':
            listas.add(p);
          case 'rechazada':
            await _devolucionDao.marcarRechazada(id, 'La venta original fue rechazada por el servidor');
            rechazadas++;
          default:
            debugPrint('[SyncService] La devolución $id espera: su venta original aún no se sincronizó.');
        }
      } catch (e, st) {
        debugPrint('[SyncService] No se pudo revisar la devolución $id: $e\n$st');
        fallidas++;
      }
    }
    if (listas.isEmpty) return ResultadoSync(rechazadas: rechazadas, fallidas: fallidas);

    final lote = {
      'enviado_en': DateTime.now().toUtc().toIso8601String(),
      'devoluciones': [
        for (final p in listas)
          {'uuid': p['devolucion_id'], ...(jsonDecode(p['payload_json'] as String) as Map<String, dynamic>)},
      ],
    };
    await _colaDao.marcarEnProceso([for (final p in listas) p['id'] as String]);

    Map<String, dynamic> respuesta;
    try {
      respuesta = await _enviar(lote);
    } catch (e, st) {
      debugPrint('[SyncService] Falló el envío de devoluciones: $e\n$st');
      for (final p in listas) {
        await _colaDao.devolverAPendiente(p['id'] as String, 'Error de envío: $e');
      }
      return ResultadoSync(rechazadas: rechazadas, fallidas: fallidas + listas.length, sesionExpirada: e is SesionExpiradaSync);
    }

    final resultados = <String, Map<String, dynamic>>{
      for (final r in (respuesta['resultados'] as List? ?? const []))
        if (r is Map && r['uuid'] is String) r['uuid'] as String: Map<String, dynamic>.from(r),
    };
    var sincronizadas = 0, enEspera = 0;
    String? motivoEspera;
    for (final p in listas) {
      final id = p['devolucion_id'] as String;
      final r = resultados[id];
      try {
        switch (r?['status']) {
          case 'ok':
            final idServidor = r!['id_servidor'];
            if (idServidor is! int) throw const FormatException('respuesta "ok" sin id_servidor');
            await _devolucionDao.marcarSincronizada(id, idServidor: idServidor);
            sincronizadas++;
          case 'conflict':
            await _devolucionDao.marcarRechazada(id, (r!['message'] as String?) ?? 'Rechazada por el servidor');
            rechazadas++;
          case 'pendiente':
            final motivo = (r!['message'] as String?) ?? 'En espera de otra operación';
            await _colaDao.devolverAPendiente(p['id'] as String, motivo);
            enEspera++;
            motivoEspera ??= motivo;
          default:
            throw FormatException('respuesta desconocida del servidor: ${r?['status']}');
        }
      } catch (e, st) {
        debugPrint('[SyncService] No se pudo procesar la devolución $id: $e\n$st');
        await _colaDao.devolverAPendiente(p['id'] as String, 'Respuesta no procesada: $e');
        fallidas++;
      }
    }
    return ResultadoSync(sincronizadas: sincronizadas, rechazadas: rechazadas, fallidas: fallidas, enEspera: enEspera, motivoEspera: motivoEspera);
  }

  /// Envía los movimientos de puntos cuya venta o devolución de origen ya está en el servidor; los demás esperan.
  /// (Si el origen fue rechazado, sus movimientos ya se anularon al rechazarlo y no llegan hasta aquí.)
  Future<ResultadoSync> _enviarPuntos(List<Map<String, dynamic>> pendientes) async {
    final listos = <Map<String, dynamic>>[];
    var fallidas = 0;
    for (final p in pendientes) {
      final id = p['movimiento_puntos_id'] as String;
      try {
        final m = await _puntosDao.obtenerParaSincronizar(id);
        if (m == null) throw StateError('el movimiento $id no existe');
        if (m['estado_origen'] == 'sincronizada') {
          listos.add(p);
        } else {
          debugPrint('[SyncService] El movimiento de puntos $id espera: su operación de origen aún no se sincronizó.');
        }
      } catch (e, st) {
        debugPrint('[SyncService] No se pudo revisar el movimiento de puntos $id: $e\n$st');
        fallidas++;
      }
    }
    if (listos.isEmpty) return ResultadoSync(fallidas: fallidas);

    final lote = {
      'enviado_en': DateTime.now().toUtc().toIso8601String(),
      'movimientos_puntos': [
        for (final p in listos)
          {'uuid': p['movimiento_puntos_id'], 'tipo_operacion': p['tipo_operacion'], ...(jsonDecode(p['payload_json'] as String) as Map<String, dynamic>)},
      ],
    };
    await _colaDao.marcarEnProceso([for (final p in listos) p['id'] as String]);

    Map<String, dynamic> respuesta;
    try {
      respuesta = await _enviar(lote);
    } catch (e, st) {
      debugPrint('[SyncService] Falló el envío de puntos: $e\n$st');
      for (final p in listos) {
        await _colaDao.devolverAPendiente(p['id'] as String, 'Error de envío: $e');
      }
      return ResultadoSync(fallidas: fallidas + listos.length, sesionExpirada: e is SesionExpiradaSync);
    }

    final resultados = <String, Map<String, dynamic>>{
      for (final r in (respuesta['resultados'] as List? ?? const []))
        if (r is Map && r['uuid'] is String) r['uuid'] as String: Map<String, dynamic>.from(r),
    };
    var sincronizadas = 0, rechazadas = 0, enEspera = 0;
    String? motivoEspera;
    for (final p in listos) {
      final id = p['movimiento_puntos_id'] as String;
      final r = resultados[id];
      try {
        switch (r?['status']) {
          case 'ok':
            await _puntosDao.marcarSincronizado(id);
            sincronizadas++;
          case 'conflict':
            await _puntosDao.marcarRechazado(id, (r!['message'] as String?) ?? 'Rechazado por el servidor');
            rechazadas++;
          case 'pendiente':
            final motivo = (r!['message'] as String?) ?? 'En espera de otra operación';
            await _colaDao.devolverAPendiente(p['id'] as String, motivo);
            enEspera++;
            motivoEspera ??= motivo;
          default:
            throw FormatException('respuesta desconocida del servidor: ${r?['status']}');
        }
      } catch (e, st) {
        debugPrint('[SyncService] No se pudo procesar el movimiento de puntos $id: $e\n$st');
        await _colaDao.devolverAPendiente(p['id'] as String, 'Respuesta no procesada: $e');
        fallidas++;
      }
    }
    return ResultadoSync(sincronizadas: sincronizadas, rechazadas: rechazadas, fallidas: fallidas, enEspera: enEspera, motivoEspera: motivoEspera);
  }

  /// Envía los cierres de caja cuyo turno ya no tiene ventas sin resolver. Si todavía queda alguna (p. ej. falló
  /// el envío y sigue pendiente) el cierre espera a la próxima sincronización, sin contarse como fallo.
  Future<ResultadoSync> _enviarCierres(List<Map<String, dynamic>> cierres) async {
    final listos = <Map<String, dynamic>>[];
    for (final c in cierres) {
      final turnoUuid = c['turno_uuid'] as String;
      if (await _turnoDao.tieneOperacionesAbiertas(turnoUuid)) {
        debugPrint('[SyncService] El cierre del turno $turnoUuid espera: hay ventas del turno sin sincronizar.');
      } else {
        listos.add(c);
      }
    }
    if (listos.isEmpty) return const ResultadoSync();

    final lote = {
      'enviado_en': DateTime.now().toUtc().toIso8601String(),
      'cierres_caja': [
        for (final c in listos)
          {'uuid': c['turno_uuid'], ...(jsonDecode(c['payload_json'] as String) as Map<String, dynamic>)},
      ],
    };
    await _colaDao.marcarEnProceso([for (final c in listos) c['id'] as String]);

    Map<String, dynamic> respuesta;
    try {
      respuesta = await _enviar(lote);
    } catch (e, st) {
      debugPrint('[SyncService] Falló el envío de cierres de caja: $e\n$st');
      for (final c in listos) {
        await _colaDao.devolverAPendiente(c['id'] as String, 'Error de envío: $e');
      }
      return ResultadoSync(fallidas: listos.length, sesionExpirada: e is SesionExpiradaSync);
    }

    final resultados = <String, Map<String, dynamic>>{
      for (final r in (respuesta['resultados'] as List? ?? const []))
        if (r is Map && r['uuid'] is String) r['uuid'] as String: Map<String, dynamic>.from(r),
    };
    var sincronizadas = 0, rechazadas = 0, fallidas = 0, enEspera = 0;
    String? motivoEspera;
    for (final c in listos) {
      final turnoUuid = c['turno_uuid'] as String;
      final r = resultados[turnoUuid];
      try {
        switch (r?['status']) {
          case 'ok':
            final idServidor = r!['id_servidor'];
            if (idServidor is! int) throw const FormatException('respuesta "ok" sin id_servidor');
            await _turnoDao.marcarCierreSincronizado(turnoUuid, idServidor: idServidor);
            sincronizadas++;
          case 'conflict':
            await _turnoDao.marcarCierreRechazado(turnoUuid, (r!['message'] as String?) ?? 'Rechazado por el servidor');
            rechazadas++;
          case 'pendiente':
            final motivo = (r!['message'] as String?) ?? 'En espera de otra operación';
            await _colaDao.devolverAPendiente(c['id'] as String, motivo);
            enEspera++;
            motivoEspera ??= motivo;
          default:
            throw FormatException('respuesta desconocida del servidor: ${r?['status']}');
        }
      } catch (e, st) {
        debugPrint('[SyncService] No se pudo procesar el cierre de $turnoUuid: $e\n$st');
        await _colaDao.devolverAPendiente(c['id'] as String, 'Respuesta no procesada: $e');
        fallidas++;
      }
    }
    return ResultadoSync(sincronizadas: sincronizadas, rechazadas: rechazadas, fallidas: fallidas, enEspera: enEspera, motivoEspera: motivoEspera);
  }

  /// Envía los QR bancarios que los clientes adjuntaron a sus pedidos cancelados (reembolso). Cada uno lleva el id de su entrada en
  /// la cola como `uuid` (clave de idempotencia: un reintento tras un corte de red no duplica nada) y la imagen en base64.
  /// No dependen de ninguna otra operación, así que nunca esperan.
  Future<ResultadoSync> _enviarQrs(List<Map<String, dynamic>> pendientes) async {
    final lote = {
      'enviado_en': DateTime.now().toUtc().toIso8601String(),
      'qr_devoluciones': [
        for (final p in pendientes) {'uuid': p['id'], ...(jsonDecode(p['payload_json'] as String) as Map<String, dynamic>)},
      ],
    };
    await _colaDao.marcarEnProceso([for (final p in pendientes) p['id'] as String]);

    Map<String, dynamic> respuesta;
    try {
      respuesta = await _enviar(lote);
    } catch (e, st) {
      debugPrint('[SyncService] Falló el envío de QR de reembolso: $e\n$st');
      for (final p in pendientes) {
        await _colaDao.devolverAPendiente(p['id'] as String, 'Error de envío: $e');
      }
      return ResultadoSync(fallidas: pendientes.length, sesionExpirada: e is SesionExpiradaSync);
    }

    final resultados = <String, Map<String, dynamic>>{
      for (final r in (respuesta['resultados'] as List? ?? const []))
        if (r is Map && r['uuid'] is String) r['uuid'] as String: Map<String, dynamic>.from(r),
    };
    var sincronizadas = 0, rechazadas = 0, fallidas = 0, enEspera = 0;
    String? motivoEspera;
    for (final p in pendientes) {
      final id = p['id'] as String;
      final r = resultados[id];
      try {
        switch (r?['status']) {
          case 'ok':
            await _qrDao.marcarSincronizado(id);
            sincronizadas++;
          case 'conflict':
            await _qrDao.marcarRechazado(id, (r!['message'] as String?) ?? 'Rechazado por el servidor');
            rechazadas++;
          case 'pendiente':
            final motivo = (r!['message'] as String?) ?? 'En espera de otra operación';
            await _colaDao.devolverAPendiente(id, motivo);
            enEspera++;
            motivoEspera ??= motivo;
          default:
            throw FormatException('respuesta desconocida del servidor: ${r?['status']}');
        }
      } catch (e, st) {
        debugPrint('[SyncService] No se pudo procesar el QR de reembolso $id: $e\n$st');
        await _colaDao.devolverAPendiente(id, 'Respuesta no procesada: $e');
        fallidas++;
      }
    }
    return ResultadoSync(sincronizadas: sincronizadas, rechazadas: rechazadas, fallidas: fallidas, enEspera: enEspera, motivoEspera: motivoEspera);
  }

  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> _armarLote(List<Map<String, dynamic>> pendientes) async {
    final operaciones = <Map<String, dynamic>>[];
    for (final p in pendientes) {
      final uuid = p['operacion_uuid'] as String;
      final payload = jsonDecode(p['payload_json'] as String) as Map<String, dynamic>;
      final cabecera = await _colaDao.obtenerCabeceraOperacion(uuid);
      operaciones.add({
        'uuid': uuid, // id local = clave de idempotencia
        'tipo_operacion': p['tipo_operacion'],
        'sucursal_id': payload['sucursal_id'],
        'cajero_id': cabecera?['cajero_id'],
        'cliente_id': cabecera?['cliente_id'],
        'fecha': cabecera?['fecha'],
        'total_centavos': cabecera?['total_centavos'],
        // CU17: puntos canjeados como descuento (el servidor aplica el mismo descuento al total de la venta)
        if ((payload['puntos_canjeados'] as int? ?? 0) > 0) 'puntos_canjeados': payload['puntos_canjeados'],
        'items': [
          for (final item in payload['items'] as List)
            {
              'producto_id': (item as Map)['producto_id'],
              'talla_id': item['talla_id'],
              'color_id': item['color_id'],
              'cantidad': item['cantidad'],
              'precio_unitario_centavos': item['precio_unitario_centavos'],
            },
        ],
      });
    }
    return {
      'enviado_en': DateTime.now().toUtc().toIso8601String(),
      'operaciones': operaciones,
    };
  }

  Future<ResultadoSync> _procesarRespuesta(List<Map<String, dynamic>> pendientes, Map<String, dynamic> respuesta) async {
    final resultados = <String, Map<String, dynamic>>{
      for (final r in (respuesta['resultados'] as List? ?? const []))
        if (r is Map && r['uuid'] is String) r['uuid'] as String: Map<String, dynamic>.from(r),
    };

    var sincronizadas = 0, rechazadas = 0, fallidas = 0, enEspera = 0, enConflicto = 0;
    String? motivoEspera;
    for (final p in pendientes) {
      final uuid = p['operacion_uuid'] as String;
      final colaId = p['id'] as String;
      final r = resultados[uuid];
      try {
        switch (r?['status']) {
          case 'ok':
            final idServidor = r!['id_servidor'];
            if (idServidor is! int) throw const FormatException('respuesta "ok" sin id_servidor');
            await _colaDao.marcarSincronizada(uuid, idServidor: idServidor);
            sincronizadas++;
          case 'conflict':
            await _colaDao.marcarRechazada(uuid, (r!['message'] as String?) ?? 'Rechazada por el servidor');
            rechazadas++;
          case 'en_conflicto':
            // CU13: el servidor guardó la venta pero sin stock suficiente. NO es un rechazo: la venta ya se hizo aquí, así que
            // se marca `en_conflicto` y NO se devuelve el stock local (el encargado la resuelve desde la web).
            await _colaDao.marcarEnConflicto(
              uuid,
              (r!['message'] as String?) ?? 'En conflicto de stock en el servidor',
              idServidor: r['id_servidor'] is int ? r['id_servidor'] as int : null,
            );
            enConflicto++;
          case 'pendiente':
            final motivo = (r!['message'] as String?) ?? 'En espera de otra operación';
            await _colaDao.devolverAPendiente(colaId, motivo); // sigue pendiente (el intento ya se contó al enviarla)
            enEspera++;
            motivoEspera ??= motivo;
          default:
            throw FormatException('respuesta desconocida del servidor: ${r?['status']}');
        }
      } catch (e, st) {
        debugPrint('[SyncService] No se pudo procesar la respuesta de $uuid: $e\n$st');
        await _colaDao.devolverAPendiente(colaId, 'Respuesta no procesada: $e');
        fallidas++;
      }
    }
    debugPrint('[SyncService] $sincronizadas sincronizadas, $rechazadas rechazadas, $enConflicto en conflicto, $fallidas por reintentar, $enEspera en espera.');
    return ResultadoSync(
      sincronizadas: sincronizadas,
      rechazadas: rechazadas,
      fallidas: fallidas,
      enEspera: enEspera,
      enConflicto: enConflicto,
      motivoEspera: motivoEspera,
    );
  }

  /// Id que se guarda cuando el servidor acepta un lote entero (`{"status": "ok"}`) sin devolver ids por operación:
  /// la tabla exige un `id_servidor` para marcar 'sincronizada'. Lo normal es que el servidor devuelva `resultados`.
  static const int idServidorDesconocido = 0;

  /// Envío real: `POST /sync/operaciones` con el token del usuario (lo pone el [DioClient]).
  Future<Map<String, dynamic>> _enviarPorHttp(Map<String, dynamic> lote) async {
    try {
      final r = await _dio.post<dynamic>(
        '/sync/operaciones',
        data: lote,
        options: Options(sendTimeout: const Duration(seconds: 30), receiveTimeout: const Duration(seconds: 30)),
      );
      return normalizarRespuesta(lote, r.data);
    } on DioException catch (e) {
      final codigo = e.response?.statusCode;
      if (codigo == 401) throw const SesionExpiradaSync();
      if (codigo == 404) {
        // El backend todavía no tiene el endpoint: no es un error de la app, la cola espera.
        throw StateError('El servidor aún no tiene /sync/operaciones (404).');
      }
      rethrow; // sin red, timeout, 5xx...: el llamador deja las operaciones pendientes
    }
  }

  /// Convierte la respuesta HTTP en `{"resultados": [...]}`. Acepta `resultados` por operación o un `status`
  /// global (`ok` / `conflict`) que se aplica a todo el lote; cualquier otra cosa se rechaza (queda pendiente).
  @visibleForTesting
  static Map<String, dynamic> normalizarRespuesta(Map<String, dynamic> lote, Object? datos) {
    if (datos is Map && datos['resultados'] is List) return Map<String, dynamic>.from(datos);
    if (datos is Map && (datos['status'] == 'ok' || datos['status'] == 'conflict')) {
      final ok = datos['status'] == 'ok';
      final idServidor = datos['id_servidor'] is int ? datos['id_servidor'] as int : idServidorDesconocido;
      final uuids = <String>[
        for (final clave in const ['operaciones', 'devoluciones', 'movimientos_puntos', 'cierres_caja', 'qr_devoluciones'])
          for (final x in (lote[clave] as List? ?? const []))
            if (x is Map && x['uuid'] is String) x['uuid'] as String,
      ];
      return {
        'resultados': [
          for (final uuid in uuids)
            {
              'uuid': uuid,
              'status': datos['status'],
              if (ok) 'id_servidor': idServidor,
              if (!ok) 'message': (datos['message'] as String?) ?? 'Rechazada por el servidor',
            },
        ],
      };
    }
    throw FormatException('respuesta no reconocida del servidor: $datos');
  }
}
