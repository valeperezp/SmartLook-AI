import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart' show Database, DatabaseException, DatabaseExecutor, Transaction;
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/schema.dart';

/// El cajero ya tiene un turno abierto en esa sucursal.
class TurnoYaAbierto implements Exception {
  TurnoYaAbierto(this.turnoUuid);

  final String turnoUuid;

  @override
  String toString() => 'Ya hay un turno abierto ($turnoUuid)';
}

/// El turno no existe o no está abierto (p. ej. ya se cerró).
class TurnoNoAbierto implements Exception {
  TurnoNoAbierto(this.turnoUuid);

  final String turnoUuid;

  @override
  String toString() => 'El turno $turnoUuid no está abierto';
}

/// Hay ventas del turno que todavía no se sincronizaron. Se pide confirmar antes de cerrar.
class OperacionesPendientesEnTurno implements Exception {
  OperacionesPendientesEnTurno(this.cantidad);

  final int cantidad;

  @override
  String toString() => '$cantidad venta(s) del turno siguen pendientes de sincronizar';
}

/// Resultado del arqueo: `diferencia = real - esperado` (positiva = sobrante, negativa = faltante).
class ResultadoArqueo {
  const ResultadoArqueo({required this.esperadoCentavos, required this.realCentavos, required this.diferenciaCentavos});

  final int esperadoCentavos;
  final int realCentavos;
  final int diferenciaCentavos;
}

/// Turnos de caja del cajero: apertura con monto inicial, arqueo al cierre y envío del cierre a la cola.
class TurnoCajaDao {
  TurnoCajaDao({AppDatabase? appDatabase}) : _appDb = appDatabase ?? AppDatabase.instance;

  final AppDatabase _appDb;
  static const _uuid = Uuid();

  Future<Database> _db() async {
    final db = await _appDb.database;
    if (db == null) {
      throw UnsupportedError('El turno de caja offline no está disponible en esta plataforma (web).');
    }
    return db;
  }

  /// Abre un turno con [montoInicialCentavos] y devuelve su UUID. Lanza [TurnoYaAbierto] si el cajero ya tiene
  /// uno abierto en la sucursal (lo garantiza también un índice único parcial en la base).
  Future<String> abrirTurno(int cajeroId, int sucursalId, int montoInicialCentavos) async {
    final db = await _db();
    if (montoInicialCentavos < 0) throw ArgumentError('El monto inicial no puede ser negativo');
    try {
      final id = _uuid.v4();
      await db.transaction((Transaction txn) async {
        final abierto = await _turnoAbierto(txn, cajeroId, sucursalId);
        if (abierto != null) throw TurnoYaAbierto(abierto['id'] as String);
        await txn.insert(Schema.tablaTurnosCaja, {
          'id': id,
          'cajero_id': cajeroId,
          'sucursal_id': sucursalId,
          'monto_inicial_centavos': montoInicialCentavos,
          'fecha_apertura': DateTime.now().toUtc().toIso8601String(),
          'estado': Schema.turnoAbierto,
        });
      });
      debugPrint('[TurnoCajaDao] Turno $id abierto (cajero $cajeroId, sucursal $sucursalId).');
      return id;
    } on DatabaseException catch (e, st) {
      // Dos aperturas simultáneas: la segunda choca con el índice único parcial
      if (e.isUniqueConstraintError()) {
        final existente = await obtenerTurnoAbierto(cajeroId, sucursalId);
        throw TurnoYaAbierto(existente?['id'] as String? ?? '?');
      }
      debugPrint('[TurnoCajaDao] Error al abrir el turno: $e\n$st');
      rethrow;
    } catch (e, st) {
      if (e is! TurnoYaAbierto) debugPrint('[TurnoCajaDao] Error al abrir el turno: $e\n$st');
      rethrow;
    }
  }

  /// El turno abierto del cajero en la sucursal, o null.
  Future<Map<String, dynamic>?> obtenerTurnoAbierto(int cajeroId, int sucursalId) async {
    final db = await _appDb.database;
    if (db == null) return null;
    try {
      return await _turnoAbierto(db, cajeroId, sucursalId);
    } catch (e, st) {
      debugPrint('[TurnoCajaDao] Error al leer el turno abierto: $e\n$st');
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> obtenerTurno(String turnoUuid) async {
    final db = await _appDb.database;
    if (db == null) return null;
    final filas = await db.query(Schema.tablaTurnosCaja, where: 'id = ?', whereArgs: [turnoUuid]);
    return filas.isEmpty ? null : filas.first;
  }

  /// Monto inicial + ventas de contado del turno + efecto neto de sus cambios/devoluciones, sin lo que el
  /// servidor haya rechazado.
  Future<int> calcularMontoEsperado(String turnoUuid) async {
    final db = await _db();
    try {
      return await _montoEsperado(db, turnoUuid);
    } catch (e, st) {
      debugPrint('[TurnoCajaDao] Error al calcular el monto esperado de $turnoUuid: $e\n$st');
      rethrow;
    }
  }

  /// Efectivo neto de los cambios/devoluciones del turno: positivo = entró dinero (el cliente pagó diferencia),
  /// negativo = salió dinero (se reembolsó). Las rechazadas no cuentan.
  Future<int> calcularMovimientoDevoluciones(String turnoUuid) async {
    final db = await _db();
    try {
      return await _movimientoDevoluciones(db, turnoUuid);
    } catch (e, st) {
      debugPrint('[TurnoCajaDao] Error al calcular las devoluciones de $turnoUuid: $e\n$st');
      rethrow;
    }
  }

  /// Ventas del turno (más recientes primero), sin las rechazadas, con su estado de sincronización.
  Future<List<Map<String, dynamic>>> listarVentasDelTurno(String turnoUuid) async {
    final db = await _db();
    try {
      return await db.query(
        Schema.tablaOperaciones,
        columns: ['uuid', 'fecha', 'total_centavos', 'estado'],
        where: "turno_uuid = ? AND tipo_operacion = 'VENTA_CONTADO' AND estado != 'rechazada'",
        whereArgs: [turnoUuid],
        orderBy: 'fecha DESC, rowid DESC',
      );
    } catch (e, st) {
      debugPrint('[TurnoCajaDao] Error al listar las ventas de $turnoUuid: $e\n$st');
      rethrow;
    }
  }

  /// Operaciones del turno (ventas y cambios/devoluciones) que siguen sin sincronizarse (cola 'pendiente' o
  /// 'en_proceso').
  Future<int> contarVentasPendientes(String turnoUuid) async {
    final db = await _db();
    try {
      return await _ventasPendientes(db, turnoUuid);
    } catch (e, st) {
      debugPrint('[TurnoCajaDao] Error al contar pendientes de $turnoUuid: $e\n$st');
      rethrow;
    }
  }

  /// Cierra el turno: calcula esperado y diferencia con [montoRealCentavos], lo marca 'cerrado' y deja un
  /// CIERRE_CAJA en `sync_queue`, todo en una transacción.
  ///
  /// Si quedan ventas del turno sin sincronizar y no se pasó [confirmarPendientes] lanza
  /// [OperacionesPendientesEnTurno] sin cambiar nada. El cierre viaja después de esas ventas.
  Future<ResultadoArqueo> cerrarTurno(
    String turnoUuid,
    int montoRealCentavos, {
    bool confirmarPendientes = false,
  }) async {
    final db = await _db();
    if (montoRealCentavos < 0) throw ArgumentError('El monto real no puede ser negativo');
    try {
      late ResultadoArqueo resultado;
      await db.transaction((Transaction txn) async {
        final filas = await txn.query(Schema.tablaTurnosCaja, where: 'id = ?', whereArgs: [turnoUuid]);
        if (filas.isEmpty || filas.first['estado'] != Schema.turnoAbierto) throw TurnoNoAbierto(turnoUuid);
        final turno = filas.first;

        final pendientes = await _ventasPendientes(txn, turnoUuid);
        if (pendientes > 0 && !confirmarPendientes) throw OperacionesPendientesEnTurno(pendientes);

        final esperado = await _montoEsperado(txn, turnoUuid);
        final diferencia = montoRealCentavos - esperado;
        final ahora = DateTime.now().toUtc().toIso8601String();
        final ventas = await txn.query(
          Schema.tablaOperaciones,
          columns: ['uuid'],
          where: "turno_uuid = ? AND tipo_operacion = 'VENTA_CONTADO' AND estado != 'rechazada'",
          whereArgs: [turnoUuid],
          orderBy: 'rowid',
        );

        await txn.update(
          Schema.tablaTurnosCaja,
          {
            'monto_esperado_centavos': esperado,
            'monto_real_centavos': montoRealCentavos,
            'diferencia_centavos': diferencia,
            'estado': Schema.turnoCerrado,
            'fecha_cierre': ahora,
          },
          where: 'id = ?',
          whereArgs: [turnoUuid],
        );
        final devoluciones = await txn.query(
          Schema.tablaDevoluciones,
          columns: ['id'],
          where: "turno_uuid = ? AND estado != 'rechazada'",
          whereArgs: [turnoUuid],
          orderBy: 'rowid',
        );
        final neto = await _movimientoDevoluciones(txn, turnoUuid);
        await txn.insert(Schema.tablaSyncQueue, {
          'id': _uuid.v4(),
          'tipo_operacion': Schema.tipoCierreCaja,
          'turno_uuid': turnoUuid,
          'payload_json': jsonEncode({
            'turno_uuid': turnoUuid,
            'cajero_id': turno['cajero_id'],
            'sucursal_id': turno['sucursal_id'],
            'fecha_apertura': turno['fecha_apertura'],
            'fecha_cierre': ahora,
            'monto_inicial_centavos': turno['monto_inicial_centavos'],
            'monto_esperado_centavos': esperado,
            'monto_real_centavos': montoRealCentavos,
            'diferencia_centavos': diferencia,
            'operaciones': [for (final v in ventas) v['uuid']],
            'devoluciones': [for (final d in devoluciones) d['id']],
            'devoluciones_neto_centavos': neto,
          }),
          'estado': Schema.estadoPendiente,
          'intentos': 0,
          'fecha_creacion': ahora,
        });
        resultado = ResultadoArqueo(
          esperadoCentavos: esperado,
          realCentavos: montoRealCentavos,
          diferenciaCentavos: diferencia,
        );
      });
      debugPrint('[TurnoCajaDao] Turno $turnoUuid cerrado: diferencia ${resultado.diferenciaCentavos} centavos.');
      return resultado;
    } catch (e, st) {
      if (e is! OperacionesPendientesEnTurno && e is! TurnoNoAbierto) {
        debugPrint('[TurnoCajaDao] Error al cerrar el turno $turnoUuid: $e\n$st');
      }
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Soporte a la sincronización del cierre
  // ---------------------------------------------------------------------------

  /// ¿Quedan operaciones del turno sin resolver en la cola? Si sí, el cierre debe esperar.
  Future<bool> tieneOperacionesAbiertas(String turnoUuid) async {
    final db = await _db();
    return await _ventasPendientes(db, turnoUuid) > 0;
  }

  /// El servidor aceptó el cierre: la cola pasa a 'sincronizado' y el turno a 'sincronizado' con su id.
  Future<void> marcarCierreSincronizado(String turnoUuid, {required int idServidor}) async {
    final db = await _db();
    try {
      await db.transaction((Transaction txn) async {
        final filas = await txn.rawUpdate(
          "UPDATE ${Schema.tablaSyncQueue} SET estado = 'sincronizado', ultimo_error = NULL, fecha_ultimo_intento = ? "
          "WHERE turno_uuid = ? AND tipo_operacion = 'CIERRE_CAJA' AND estado IN ('pendiente', 'en_proceso')",
          [DateTime.now().toUtc().toIso8601String(), turnoUuid],
        );
        if (filas != 1) throw StateError('El cierre del turno $turnoUuid no está pendiente de sincronizar.');
        await txn.rawUpdate(
          'UPDATE ${Schema.tablaTurnosCaja} SET estado = ?, id_servidor = ? WHERE id = ? AND estado = ?',
          [Schema.turnoSincronizado, idServidor, turnoUuid, Schema.turnoCerrado],
        );
      });
    } catch (e, st) {
      debugPrint('[TurnoCajaDao] Error al marcar sincronizado el cierre de $turnoUuid: $e\n$st');
      rethrow;
    }
  }

  /// El servidor rechazó el cierre: la cola queda 'rechazado' con el motivo y el turno sigue 'cerrado'
  /// (necesita revisión; no se reintenta solo).
  Future<void> marcarCierreRechazado(String turnoUuid, String motivo) async {
    final db = await _db();
    try {
      final filas = await db.rawUpdate(
        "UPDATE ${Schema.tablaSyncQueue} SET estado = 'rechazado', ultimo_error = ?, fecha_ultimo_intento = ? "
        "WHERE turno_uuid = ? AND tipo_operacion = 'CIERRE_CAJA' AND estado IN ('pendiente', 'en_proceso')",
        [motivo, DateTime.now().toUtc().toIso8601String(), turnoUuid],
      );
      if (filas != 1) throw StateError('El cierre del turno $turnoUuid no está pendiente de sincronizar.');
    } catch (e, st) {
      debugPrint('[TurnoCajaDao] Error al marcar rechazado el cierre de $turnoUuid: $e\n$st');
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>?> _turnoAbierto(DatabaseExecutor executor, int cajeroId, int sucursalId) async {
    final filas = await executor.query(
      Schema.tablaTurnosCaja,
      where: 'cajero_id = ? AND sucursal_id = ? AND estado = ?',
      whereArgs: [cajeroId, sucursalId, Schema.turnoAbierto],
      limit: 1,
    );
    return filas.isEmpty ? null : filas.first;
  }

  Future<int> _montoEsperado(DatabaseExecutor executor, String turnoUuid) async {
    final turno = await executor.query(
      Schema.tablaTurnosCaja,
      columns: ['monto_inicial_centavos'],
      where: 'id = ?',
      whereArgs: [turnoUuid],
    );
    if (turno.isEmpty) throw TurnoNoAbierto(turnoUuid);
    final ventas = await executor.rawQuery(
      'SELECT COALESCE(SUM(total_centavos), 0) AS suma FROM ${Schema.tablaOperaciones} '
      "WHERE turno_uuid = ? AND tipo_operacion = 'VENTA_CONTADO' AND estado != 'rechazada'",
      [turnoUuid],
    );
    final devoluciones = await _movimientoDevoluciones(executor, turnoUuid);
    return (turno.first['monto_inicial_centavos'] as int) + (ventas.first['suma'] as int) + devoluciones;
  }

  Future<int> _movimientoDevoluciones(DatabaseExecutor executor, String turnoUuid) async {
    final filas = await executor.rawQuery(
      'SELECT COALESCE(SUM(total_nuevo_centavos - total_devuelto_centavos), 0) AS neto '
      "FROM ${Schema.tablaDevoluciones} WHERE turno_uuid = ? AND estado != 'rechazada'",
      [turnoUuid],
    );
    return filas.first['neto'] as int;
  }

  Future<int> _ventasPendientes(DatabaseExecutor executor, String turnoUuid) async {
    final filas = await executor.rawQuery(
      'SELECT '
      '(SELECT COUNT(*) FROM ${Schema.tablaSyncQueue} q '
      ' JOIN ${Schema.tablaOperaciones} o ON o.uuid = q.operacion_uuid '
      " WHERE o.turno_uuid = ? AND q.estado IN ('pendiente', 'en_proceso')) + "
      '(SELECT COUNT(*) FROM ${Schema.tablaSyncQueue} q '
      ' JOIN ${Schema.tablaDevoluciones} d ON d.id = q.devolucion_id '
      " WHERE d.turno_uuid = ? AND q.estado IN ('pendiente', 'en_proceso')) AS n",
      [turnoUuid, turnoUuid],
    );
    return filas.first['n'] as int;
  }
}
