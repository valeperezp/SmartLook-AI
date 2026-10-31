import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart' show Database, DatabaseExecutor, Transaction;
import 'package:uuid/uuid.dart';

import '../../../core/config/offline_config.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/schema.dart';

/// Puntos de fidelización del cliente (CU17): saldo, movimientos y su envío al servidor.
///
/// Los puntos se ganan con las ventas de contado (1 por cada $10, ver [OfflineConfig]) y se pierden, en
/// proporción, con las devoluciones. El saldo nunca baja de 0 (lo garantiza también un CHECK de la tabla).
/// Cada movimiento deja un PUNTOS_OTORGADOS / PUNTOS_RESTADOS en `sync_queue`, que se envía una vez que la
/// venta o devolución de origen ya está en el servidor.
///
/// Los métodos `...En` corren dentro de la transacción del llamador (así la venta y sus puntos son atómicos).
class PuntosDao {
  PuntosDao({AppDatabase? appDatabase}) : _appDb = appDatabase ?? AppDatabase.instance;

  final AppDatabase _appDb;
  static const _uuid = Uuid();

  Future<Database> _db() async {
    final db = await _appDb.database;
    if (db == null) {
      throw UnsupportedError('Los puntos de fidelización offline no están disponibles en esta plataforma (web).');
    }
    return db;
  }

  // ---------------------------------------------------------------------------
  // API pública (cada método abre su propia transacción)
  // ---------------------------------------------------------------------------

  /// Suma los puntos de una venta de [totalCentavos] al saldo de [clienteId]. Devuelve los puntos otorgados
  /// (0 si la compra no llega a un punto; en ese caso no se registra nada).
  Future<int> otorgarPuntos(int clienteId, String operacionUuid, int totalCentavos) async {
    final db = await _db();
    try {
      return await db.transaction((txn) => otorgarEn(txn, clienteId, operacionUuid, totalCentavos));
    } catch (e, st) {
      debugPrint('[PuntosDao] Error al otorgar puntos a $clienteId: $e\n$st');
      rethrow;
    }
  }

  /// Resta puntos a [clienteId] por devolver [montoDevueltoCentavos] de la venta [ventaUuid], de forma
  /// proporcional a lo que esa venta le dio (sumando lo devuelto antes). Devuelve los puntos descontados.
  Future<int> restarPuntos(int clienteId, String ventaUuid, int montoDevueltoCentavos, {String? devolucionId}) async {
    final db = await _db();
    try {
      return await db.transaction((txn) async {
        final venta = await txn.query(Schema.tablaOperaciones, columns: ['total_centavos'], where: 'uuid = ?', whereArgs: [ventaUuid]);
        if (venta.isEmpty) throw StateError('La venta $ventaUuid no existe.');
        final previo = await devueltoEnDevoluciones(txn, ventaUuid);
        return restarEn(
          txn,
          clienteId: clienteId,
          ventaUuid: ventaUuid,
          origenUuid: devolucionId ?? _uuid.v4(),
          totalVentaCentavos: venta.first['total_centavos'] as int,
          devueltoAcumuladoCentavos: previo + montoDevueltoCentavos,
        );
      });
    } catch (e, st) {
      debugPrint('[PuntosDao] Error al restar puntos a $clienteId: $e\n$st');
      rethrow;
    }
  }

  /// Saldo actual (0 si el cliente nunca tuvo puntos).
  Future<int> obtenerSaldo(int clienteId) async {
    final db = await _appDb.database;
    if (db == null) return 0;
    try {
      final filas = await db.query(Schema.tablaPuntosCliente, columns: ['saldo'], where: 'cliente_id = ?', whereArgs: [clienteId]);
      return filas.isEmpty ? 0 : filas.first['saldo'] as int;
    } catch (e, st) {
      debugPrint('[PuntosDao] Error al leer el saldo de $clienteId: $e\n$st');
      rethrow;
    }
  }

  /// Últimos movimientos del cliente (más recientes primero), sin los rechazados/cancelados.
  Future<List<Map<String, dynamic>>> listarMovimientos(int clienteId, {int limite = 30}) async {
    final db = await _appDb.database;
    if (db == null) return const [];
    try {
      return await db.query(
        Schema.tablaMovimientosPuntos,
        where: "cliente_id = ? AND estado_sync != 'rechazado'",
        whereArgs: [clienteId],
        orderBy: 'fecha DESC, rowid DESC',
        limit: limite,
      );
    } catch (e, st) {
      debugPrint('[PuntosDao] Error al listar movimientos de $clienteId: $e\n$st');
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Sincronización
  // ---------------------------------------------------------------------------

  /// El movimiento con el estado de su venta/devolución de origen (`estado_origen`), o null.
  Future<Map<String, dynamic>?> obtenerParaSincronizar(String movimientoId) async {
    final db = await _db();
    final filas = await db.rawQuery(
      'SELECT m.*, COALESCE((SELECT estado FROM ${Schema.tablaOperaciones} WHERE uuid = m.operacion_uuid), '
      '(SELECT estado FROM ${Schema.tablaDevoluciones} WHERE id = m.operacion_uuid)) AS estado_origen '
      'FROM ${Schema.tablaMovimientosPuntos} m WHERE m.id = ?',
      [movimientoId],
    );
    return filas.isEmpty ? null : {...filas.first};
  }

  /// El servidor aceptó el movimiento: movimiento y cola quedan 'sincronizado'.
  Future<void> marcarSincronizado(String movimientoId) async {
    final db = await _db();
    try {
      await db.transaction((txn) async {
        await _cerrarCola(txn, movimientoId, 'sincronizado', null);
        await txn.update(Schema.tablaMovimientosPuntos, {'estado_sync': 'sincronizado'}, where: 'id = ?', whereArgs: [movimientoId]);
      });
    } catch (e, st) {
      debugPrint('[PuntosDao] Error al marcar sincronizado $movimientoId: $e\n$st');
      rethrow;
    }
  }

  /// El servidor rechazó el movimiento: se deshace su efecto en el saldo.
  Future<void> marcarRechazado(String movimientoId, String motivo) async {
    final db = await _db();
    try {
      await db.transaction((txn) async {
        await _cerrarCola(txn, movimientoId, 'rechazado', motivo);
        await _anularMovimiento(txn, movimientoId);
      });
    } catch (e, st) {
      debugPrint('[PuntosDao] Error al rechazar $movimientoId: $e\n$st');
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Operaciones dentro de la transacción del llamador
  // ---------------------------------------------------------------------------

  static Future<int> otorgarEn(DatabaseExecutor txn, int clienteId, String operacionUuid, int totalCentavos) async {
    final puntos = OfflineConfig.puntosPara(totalCentavos);
    if (puntos <= 0) return 0;
    await _registrarMovimiento(
      txn,
      clienteId: clienteId,
      operacionUuid: operacionUuid,
      ventaUuid: operacionUuid,
      tipo: Schema.puntosGanado,
      cantidad: puntos,
      tipoCola: Schema.tipoPuntosOtorgados,
    );
    return puntos;
  }

  /// Resta los puntos que corresponden a lo devuelto hasta ahora de la venta, descontando lo ya restado.
  ///
  /// Proporción: `puntos_ganados × devuelto_acumulado / total_venta` (redondeado). Así devolver toda la venta
  /// quita exactamente lo ganado, aunque se haga en varias devoluciones. Nunca deja el saldo en negativo.
  static Future<int> restarEn(
    DatabaseExecutor txn, {
    required int clienteId,
    required String ventaUuid,
    required String origenUuid,
    required int totalVentaCentavos,
    required int devueltoAcumuladoCentavos,
  }) async {
    if (totalVentaCentavos <= 0) return 0;
    final ganados = await _sumaMovimientos(txn, ventaUuid, Schema.puntosGanado);
    if (ganados <= 0) return 0;
    final yaPerdidos = await _sumaMovimientos(txn, ventaUuid, Schema.puntosPerdido);

    final devuelto = devueltoAcumuladoCentavos.clamp(0, totalVentaCentavos);
    final objetivo = (ganados * devuelto * 2 + totalVentaCentavos) ~/ (2 * totalVentaCentavos); // redondeo normal
    final saldo = await _saldo(txn, clienteId);
    final aPerder = (objetivo - yaPerdidos).clamp(0, saldo);
    if (aPerder <= 0) return 0;

    await _registrarMovimiento(
      txn,
      clienteId: clienteId,
      operacionUuid: origenUuid,
      ventaUuid: ventaUuid,
      tipo: Schema.puntosPerdido,
      cantidad: aPerder,
      tipoCola: Schema.tipoPuntosRestados,
    );
    return aPerder;
  }

  /// Total devuelto (en dinero) de una venta en cambios/devoluciones no rechazados.
  static Future<int> devueltoEnDevoluciones(DatabaseExecutor txn, String ventaUuid) async {
    final filas = await txn.rawQuery(
      'SELECT COALESCE(SUM(total_devuelto_centavos), 0) AS n FROM ${Schema.tablaDevoluciones} '
      "WHERE venta_uuid = ? AND estado != 'rechazada'",
      [ventaUuid],
    );
    return filas.first['n'] as int;
  }

  /// La venta o devolución [operacionUuid] fue rechazada: sus movimientos de puntos todavía sin enviar se anulan
  /// (el saldo vuelve a como estaba) y sus entradas de cola se rechazan.
  static Future<void> cancelarPorOperacionEn(DatabaseExecutor txn, String operacionUuid) async {
    final movimientos = await txn.query(
      Schema.tablaMovimientosPuntos,
      columns: ['id'],
      where: "operacion_uuid = ? AND estado_sync = 'pendiente'",
      whereArgs: [operacionUuid],
    );
    for (final m in movimientos) {
      final id = m['id'] as String;
      await txn.rawUpdate(
        "UPDATE ${Schema.tablaSyncQueue} SET estado = 'rechazado', ultimo_error = ?, fecha_ultimo_intento = ? "
        "WHERE movimiento_puntos_id = ? AND estado IN ('pendiente', 'en_proceso')",
        ['La operación de origen fue rechazada', DateTime.now().toUtc().toIso8601String(), id],
      );
      await _anularMovimiento(txn, id);
    }
  }

  // ---------------------------------------------------------------------------

  static Future<void> _registrarMovimiento(
    DatabaseExecutor txn, {
    required int clienteId,
    required String operacionUuid,
    required String ventaUuid,
    required String tipo,
    required int cantidad,
    required String tipoCola,
  }) async {
    final ahora = DateTime.now().toUtc().toIso8601String();
    final id = _uuid.v4();
    await txn.rawInsert(
      'INSERT OR IGNORE INTO ${Schema.tablaPuntosCliente} (cliente_id, saldo, ultima_actualizacion) VALUES (?, 0, ?)',
      [clienteId, ahora],
    );
    final delta = tipo == Schema.puntosGanado ? cantidad : -cantidad;
    await txn.rawUpdate(
      'UPDATE ${Schema.tablaPuntosCliente} SET saldo = MAX(saldo + ?, 0), ultima_actualizacion = ? WHERE cliente_id = ?',
      [delta, ahora, clienteId],
    );
    await txn.insert(Schema.tablaMovimientosPuntos, {
      'id': id,
      'cliente_id': clienteId,
      'operacion_uuid': operacionUuid,
      'venta_uuid': ventaUuid,
      'tipo': tipo,
      'cantidad': cantidad,
      'fecha': ahora,
    });
    await txn.insert(Schema.tablaSyncQueue, {
      'id': _uuid.v4(),
      'tipo_operacion': tipoCola,
      'movimiento_puntos_id': id,
      'payload_json': jsonEncode({
        'movimiento_id': id,
        'cliente_id': clienteId,
        'operacion_uuid': operacionUuid,
        'venta_uuid': ventaUuid,
        'tipo': tipo,
        'cantidad': cantidad,
        'fecha': ahora,
      }),
      'estado': Schema.estadoPendiente,
      'intentos': 0,
      'fecha_creacion': ahora,
    });
  }

  /// Deshace el efecto del movimiento en el saldo y lo marca 'rechazado'.
  static Future<void> _anularMovimiento(DatabaseExecutor txn, String movimientoId) async {
    final filas = await txn.query(Schema.tablaMovimientosPuntos, where: 'id = ?', whereArgs: [movimientoId]);
    if (filas.isEmpty) return;
    final m = filas.first;
    final delta = m['tipo'] == Schema.puntosGanado ? -(m['cantidad'] as int) : (m['cantidad'] as int);
    await txn.rawUpdate(
      'UPDATE ${Schema.tablaPuntosCliente} SET saldo = MAX(saldo + ?, 0), ultima_actualizacion = ? WHERE cliente_id = ?',
      [delta, DateTime.now().toUtc().toIso8601String(), m['cliente_id']],
    );
    await txn.update(Schema.tablaMovimientosPuntos, {'estado_sync': 'rechazado'}, where: 'id = ?', whereArgs: [movimientoId]);
  }

  static Future<void> _cerrarCola(Transaction txn, String movimientoId, String estado, String? motivo) async {
    final filas = await txn.rawUpdate(
      'UPDATE ${Schema.tablaSyncQueue} SET estado = ?, ultimo_error = ?, fecha_ultimo_intento = ? '
      "WHERE movimiento_puntos_id = ? AND estado IN ('pendiente', 'en_proceso')",
      [estado, motivo, DateTime.now().toUtc().toIso8601String(), movimientoId],
    );
    if (filas != 1) throw StateError('El movimiento $movimientoId no está pendiente de sincronizar.');
  }

  static Future<int> _sumaMovimientos(DatabaseExecutor txn, String ventaUuid, String tipo) async {
    final filas = await txn.rawQuery(
      'SELECT COALESCE(SUM(cantidad), 0) AS n FROM ${Schema.tablaMovimientosPuntos} '
      "WHERE venta_uuid = ? AND tipo = ? AND estado_sync != 'rechazado'",
      [ventaUuid, tipo],
    );
    return filas.first['n'] as int;
  }

  static Future<int> _saldo(DatabaseExecutor txn, int clienteId) async {
    final filas = await txn.query(Schema.tablaPuntosCliente, columns: ['saldo'], where: 'cliente_id = ?', whereArgs: [clienteId]);
    return filas.isEmpty ? 0 : filas.first['saldo'] as int;
  }
}
