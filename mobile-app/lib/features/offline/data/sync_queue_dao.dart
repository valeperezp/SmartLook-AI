import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart' show Transaction;
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/schema.dart';
import 'puntos_dao.dart';
import 'turno_caja_dao.dart';

/// El stock local no alcanza para la cantidad pedida (otra operación offline ya lo consumió).
class StockLocalInsuficiente implements Exception {
  StockLocalInsuficiente(this.inventarioId);

  final int inventarioId;

  @override
  String toString() => 'Stock local insuficiente para el inventario $inventarioId';
}

/// Operaciones hechas sin conexión (venta de contado del cajero / reserva del cliente) y su cola de sincronización.
class SyncQueueDao {
  SyncQueueDao({AppDatabase? appDatabase}) : _appDb = appDatabase ?? AppDatabase.instance;

  final AppDatabase _appDb;
  static const _uuid = Uuid();
  static const _marcaStockDescontado = 'stock_local_descontado';

  /// Guarda en UNA sola transacción la cabecera (`operaciones_locales`), sus ítems y la entrada en
  /// `sync_queue` (estado 'pendiente'). Si algo falla no queda nada a medias. Devuelve el id de la cola.
  ///
  /// [json] debe traer:
  /// - `sucursal_id` (int)
  /// - `cajero_id` (int) — obligatorio en VENTA_CONTADO
  /// - `items`: lista de `{producto_id, talla_id?, color_id?, nombre_producto, cantidad, precio_unitario_centavos}`
  /// - opcionales: `total_centavos` (si falta se calcula de los ítems) y `fecha` (ISO-8601, por defecto ahora UTC)
  /// Cualquier otra clave (p. ej. `horario_aproximado` de una reserva) viaja solo dentro de `payload_json`.
  ///
  /// [clienteId] es obligatorio en RESERVA_CLIENTE y puede ser null en VENTA_CONTADO.
  ///
  /// [turnoUuid] vincula una VENTA_CONTADO al turno de caja abierto del cajero (las reservas no tienen turno).
  /// Se comprueba dentro de la transacción que el turno exista y siga abierto; si no, lanza [TurnoNoAbierto].
  ///
  /// Con [descontarStockLocal] (descuento optimista) cada ítem debe traer además `inventario_id` y se resta
  /// su `cantidad` de `catalogo_local` en la MISMA transacción. Si no alcanza el stock local lanza
  /// [StockLocalInsuficiente] y no se guarda nada.
  Future<String> guardarOperacionOffline(
    Map<String, dynamic> json,
    String uuid,
    String tipoOperacion,
    int? clienteId, {
    bool descontarStockLocal = false,
    String? turnoUuid,
  }) async {
    final db = await _appDb.database;
    if (db == null) {
      throw UnsupportedError('Las operaciones offline no están disponibles en esta plataforma (web).');
    }

    try {
      if (turnoUuid != null && tipoOperacion != Schema.tipoVentaContado) {
        throw ArgumentError('Solo una VENTA_CONTADO puede vincularse a un turno de caja');
      }
      final cabecera = _validarYArmarCabecera(json, uuid, tipoOperacion, clienteId)..['turno_uuid'] = turnoUuid;
      final items = _validarYArmarItems(json['items'], uuid);
      final descuentos = descontarStockLocal ? _validarDescuentos(json['items']) : const <(int, int)>[];
      final colaId = _uuid.v4();
      final ahora = DateTime.now().toUtc().toIso8601String();

      await db.transaction((txn) async {
        if (turnoUuid != null) {
          final turno = await txn.query(Schema.tablaTurnosCaja, columns: ['estado'], where: 'id = ?', whereArgs: [turnoUuid]);
          if (turno.isEmpty || turno.first['estado'] != Schema.turnoAbierto) throw TurnoNoAbierto(turnoUuid);
        }
        await txn.insert(Schema.tablaOperaciones, cabecera);
        final batch = txn.batch();
        for (final item in items) {
          batch.insert(Schema.tablaOperacionesItems, item);
        }
        await batch.commit(noResult: true);
        for (final (inventarioId, cantidad) in descuentos) {
          final filas = await txn.rawUpdate(
            'UPDATE ${Schema.tablaCatalogoLocal} SET cantidad_disponible = cantidad_disponible - ? '
            'WHERE inventario_id = ? AND cantidad_disponible >= ?',
            [cantidad, inventarioId, cantidad],
          );
          if (filas != 1) throw StockLocalInsuficiente(inventarioId);
        }
        await txn.insert(Schema.tablaSyncQueue, {
          'id': colaId,
          'tipo_operacion': tipoOperacion,
          'operacion_uuid': uuid,
          // La marca indica que ESTA operación restó stock local: si el servidor la rechaza hay que devolverlo.
          'payload_json': jsonEncode({...json, if (descontarStockLocal) _marcaStockDescontado: true}),
          'estado': Schema.estadoPendiente,
          'intentos': 0,
          'fecha_creacion': ahora,
        });
        // Fidelización (CU17): una venta de contado con cliente le da puntos, en la misma transacción
        if (tipoOperacion == Schema.tipoVentaContado && clienteId != null) {
          await PuntosDao.otorgarEn(txn, clienteId, uuid, cabecera['total_centavos'] as int);
        }
      });

      debugPrint('[SyncQueueDao] Operación $tipoOperacion $uuid encolada ($colaId, ${items.length} ítems).');
      return colaId;
    } catch (e, st) {
      debugPrint('[SyncQueueDao] Error al guardar la operación offline $uuid: $e\n$st');
      rethrow;
    }
  }

  /// Operaciones con estado 'pendiente', de la más antigua a la más nueva (orden de envío).
  Future<List<Map<String, dynamic>>> obtenerOperacionesPendientes() async {
    final db = await _appDb.database;
    if (db == null) return const [];

    try {
      return await db.query(
        Schema.tablaSyncQueue,
        where: 'estado = ?',
        whereArgs: [Schema.estadoPendiente],
        orderBy: 'fecha_creacion ASC, rowid ASC',
      );
    } catch (e, st) {
      debugPrint('[SyncQueueDao] Error al leer operaciones pendientes: $e\n$st');
      rethrow;
    }
  }

  /// Cabecera de `operaciones_locales` (cliente_id, cajero_id, fecha...) o null si no existe.
  Future<Map<String, dynamic>?> obtenerCabeceraOperacion(String uuid) async {
    final db = await _appDb.database;
    if (db == null) return null;
    try {
      final filas = await db.query(Schema.tablaOperaciones, where: 'uuid = ?', whereArgs: [uuid]);
      return filas.isEmpty ? null : filas.first;
    } catch (e, st) {
      debugPrint('[SyncQueueDao] Error al leer la cabecera $uuid: $e\n$st');
      rethrow;
    }
  }

  /// Marca las entradas [colaIds] como 'en_proceso' (se están enviando): suma un intento y anota la hora.
  Future<void> marcarEnProceso(List<String> colaIds) async {
    final db = await _appDb.database;
    if (db == null || colaIds.isEmpty) return;
    try {
      final ahora = DateTime.now().toUtc().toIso8601String();
      await db.transaction((txn) async {
        for (final id in colaIds) {
          await txn.rawUpdate(
            "UPDATE ${Schema.tablaSyncQueue} SET estado = 'en_proceso', intentos = intentos + 1, "
            "fecha_ultimo_intento = ? WHERE id = ? AND estado = 'pendiente'",
            [ahora, id],
          );
        }
      });
    } catch (e, st) {
      debugPrint('[SyncQueueDao] Error al marcar en proceso: $e\n$st');
      rethrow;
    }
  }

  /// Recupera entradas que quedaron 'en_proceso' (la app se cerró a mitad de un envío): vuelven a 'pendiente'.
  Future<int> liberarOperacionesEnProceso() async {
    final db = await _appDb.database;
    if (db == null) return 0;
    try {
      return await db.rawUpdate(
        "UPDATE ${Schema.tablaSyncQueue} SET estado = 'pendiente' WHERE estado = 'en_proceso'",
      );
    } catch (e, st) {
      debugPrint('[SyncQueueDao] Error al liberar operaciones en proceso: $e\n$st');
      rethrow;
    }
  }

  /// Fallo transitorio (sin red, error del servidor): la entrada vuelve a 'pendiente' para reintentarse.
  Future<void> devolverAPendiente(String colaId, String motivo) async {
    final db = await _appDb.database;
    if (db == null) return;
    try {
      await db.rawUpdate(
        "UPDATE ${Schema.tablaSyncQueue} SET estado = 'pendiente', ultimo_error = ? "
        "WHERE id = ? AND estado = 'en_proceso'",
        [motivo, colaId],
      );
    } catch (e, st) {
      debugPrint('[SyncQueueDao] Error al devolver a pendiente $colaId: $e\n$st');
      rethrow;
    }
  }

  /// El servidor aceptó la operación [uuid]: `sync_queue` pasa a 'sincronizado' y `operaciones_locales` a
  /// 'sincronizada' con el id que le dio el servidor (la tabla exige que exista). Una sola transacción.
  Future<void> marcarSincronizada(String uuid, {required int idServidor}) {
    return _cerrarOperacion(
      uuid,
      estadoCola: 'sincronizado',
      estadoOperacion: 'sincronizada',
      motivo: null,
      idServidor: idServidor,
    );
  }

  /// El servidor rechazó la operación [uuid] (p. ej. stock insuficiente): queda 'rechazado' / 'rechazada' con el
  /// [motivo]. No se reintenta. En la MISMA transacción se devuelve a `catalogo_local` el stock que esa operación
  /// había descontado (ver [_devolverStockLocal]). Devuelve cuántas variantes recuperaron stock.
  Future<int> marcarRechazada(String uuid, String motivo) async {
    var devueltas = 0;
    await _cerrarOperacion(
      uuid,
      estadoCola: 'rechazado',
      estadoOperacion: 'rechazada',
      motivo: motivo,
      idServidor: null,
      antesDeCerrar: (txn) async {
        devueltas = await _devolverStockLocal(txn, uuid);
        await PuntosDao.cancelarPorOperacionEn(txn, uuid); // los puntos de una venta rechazada se anulan
      },
    );
    return devueltas;
  }

  /// Suma de vuelta al catálogo local las cantidades de los ítems de [uuid], y solo si:
  /// - la operación realmente descontó stock local (marca en su payload), y
  /// - la fila del catálogo no se refrescó desde el servidor DESPUÉS de la operación (si se refrescó, esa
  ///   cantidad ya es la real del servidor y sumarla la inflaría).
  /// La variante se ubica por (sucursal, producto, talla, color), que es única en `catalogo_local`.
  Future<int> _devolverStockLocal(Transaction txn, String uuid) async {
    final cola = await txn.query(
      Schema.tablaSyncQueue,
      columns: ['payload_json', 'fecha_creacion'],
      where: 'operacion_uuid = ?',
      whereArgs: [uuid],
    );
    if (cola.isEmpty) return 0;
    final payload = jsonDecode(cola.first['payload_json'] as String) as Map<String, dynamic>;
    if (payload[_marcaStockDescontado] != true) return 0;
    final fechaOperacion = cola.first['fecha_creacion'] as String;

    final cabecera = await txn.query(Schema.tablaOperaciones, columns: ['sucursal_id'], where: 'uuid = ?', whereArgs: [uuid]);
    final sucursalId = cabecera.first['sucursal_id'] as int;
    final items = await txn.query(Schema.tablaOperacionesItems, where: 'operacion_uuid = ?', whereArgs: [uuid]);

    var devueltas = 0;
    for (final item in items) {
      final filas = await txn.rawUpdate(
        'UPDATE ${Schema.tablaCatalogoLocal} SET cantidad_disponible = cantidad_disponible + ? '
        'WHERE sucursal_id = ? AND producto_id = ? AND IFNULL(talla_id, 0) = IFNULL(?, 0) '
        'AND IFNULL(color_id, 0) = IFNULL(?, 0) AND sincronizado_en <= ?',
        [item['cantidad'], sucursalId, item['producto_id'], item['talla_id'], item['color_id'], fechaOperacion],
      );
      devueltas += filas;
    }
    debugPrint('[SyncQueueDao] Rechazo de $uuid: stock devuelto en $devueltas de ${items.length} variantes.');
    return devueltas;
  }

  /// CU13: el servidor guardó la venta [uuid] pero SIN stock suficiente (queda `en_conflicto` en el servidor, a la
  /// espera de que un encargado la resuelva desde la web). La venta ya se hizo en este dispositivo, así que NO se
  /// devuelve el stock local ni se anulan sus puntos. No se reenvía. [idServidor] es el id de la venta en el servidor.
  Future<void> marcarEnConflicto(String uuid, String motivo, {int? idServidor}) {
    return _cerrarOperacion(
      uuid,
      estadoCola: 'en_conflicto',
      estadoOperacion: 'en_conflicto',
      motivo: motivo,
      idServidor: idServidor,
    );
  }

  Future<void> _cerrarOperacion(
    String uuid, {
    required String estadoCola,
    required String estadoOperacion,
    required String? motivo,
    required int? idServidor,
    Future<void> Function(Transaction txn)? antesDeCerrar,
  }) async {
    final db = await _appDb.database;
    if (db == null) {
      throw UnsupportedError('Las operaciones offline no están disponibles en esta plataforma (web).');
    }
    try {
      await db.transaction((txn) async {
        // Solo se cierra lo que sigue abierto: una operación ya sincronizada/rechazada no se pisa.
        // (La comprobación va primero: así el stock nunca se devuelve dos veces.)
        final abierta = await txn.query(
          Schema.tablaSyncQueue,
          columns: ['id'],
          where: "operacion_uuid = ? AND estado IN ('pendiente', 'en_proceso')",
          whereArgs: [uuid],
        );
        if (abierta.length != 1) throw StateError('La operación $uuid no está pendiente de sincronizar.');
        await antesDeCerrar?.call(txn);
        final filas = await txn.rawUpdate(
          'UPDATE ${Schema.tablaSyncQueue} SET estado = ?, ultimo_error = ?, fecha_ultimo_intento = ? '
          "WHERE operacion_uuid = ? AND estado IN ('pendiente', 'en_proceso')",
          [estadoCola, motivo, DateTime.now().toUtc().toIso8601String(), uuid],
        );
        if (filas != 1) throw StateError('La operación $uuid no está pendiente de sincronizar.');
        await txn.rawUpdate(
          'UPDATE ${Schema.tablaOperaciones} SET estado = ?, id_servidor = ? WHERE uuid = ?',
          [estadoOperacion, idServidor, uuid],
        );
      });
    } catch (e, st) {
      debugPrint('[SyncQueueDao] Error al cerrar la operación $uuid como $estadoCola: $e\n$st');
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Validación (los CHECK de la base son la última barrera; aquí se falla con un mensaje claro)
  // ---------------------------------------------------------------------------

  Map<String, Object?> _validarYArmarCabecera(
    Map<String, dynamic> json,
    String uuid,
    String tipoOperacion,
    int? clienteId,
  ) {
    if (uuid.isEmpty) throw ArgumentError('uuid vacío');
    if (!Schema.tiposOperacion.contains(tipoOperacion)) {
      throw ArgumentError('tipoOperacion inválido: $tipoOperacion (usar ${Schema.tiposOperacion.join(" o ")})');
    }

    final sucursalId = json['sucursal_id'];
    if (sucursalId is! int) throw ArgumentError('sucursal_id (int) es obligatorio');

    final cajeroId = json['cajero_id'];
    if (cajeroId != null && cajeroId is! int) throw ArgumentError('cajero_id debe ser int');
    if (tipoOperacion == Schema.tipoVentaContado && cajeroId == null) {
      throw ArgumentError('cajero_id es obligatorio en VENTA_CONTADO');
    }
    if (tipoOperacion == Schema.tipoReservaCliente && clienteId == null) {
      throw ArgumentError('clienteId es obligatorio en RESERVA_CLIENTE');
    }

    final items = json['items'];
    final total = json['total_centavos'] ?? _calcularTotal(items);

    return {
      'uuid': uuid,
      'tipo_operacion': tipoOperacion,
      'sucursal_id': sucursalId,
      'cajero_id': cajeroId,
      'cliente_id': clienteId,
      'total_centavos': total,
      'fecha': json['fecha'] ?? DateTime.now().toUtc().toIso8601String(),
    };
  }

  List<Map<String, Object?>> _validarYArmarItems(Object? items, String operacionUuid) {
    if (items is! List || items.isEmpty) throw ArgumentError('items debe ser una lista no vacía');

    return [
      for (final (i, item) in items.indexed)
        if (item is! Map || item['producto_id'] is! int || item['cantidad'] is! int ||
            item['precio_unitario_centavos'] is! int || item['nombre_producto'] is! String)
          throw ArgumentError(
            'items[$i] inválido: requiere producto_id, cantidad, precio_unitario_centavos (int) y nombre_producto (String)',
          )
        else
          {
            'operacion_uuid': operacionUuid,
            'producto_id': item['producto_id'],
            'talla_id': item['talla_id'],
            'color_id': item['color_id'],
            'nombre_producto': item['nombre_producto'],
            'cantidad': item['cantidad'],
            'precio_unitario_centavos': item['precio_unitario_centavos'],
          },
    ];
  }

  /// (inventario_id, cantidad) de cada ítem; ya se validó la forma de los ítems en [_validarYArmarItems].
  List<(int, int)> _validarDescuentos(Object? items) {
    return [
      for (final (i, item) in (items as List).indexed)
        if ((item as Map)['inventario_id'] is! int)
          throw ArgumentError('items[$i].inventario_id (int) es obligatorio para descontar stock local')
        else
          (item['inventario_id'] as int, item['cantidad'] as int),
    ];
  }

  int _calcularTotal(Object? items) {
    if (items is! List) return 0;
    var total = 0;
    for (final item in items) {
      if (item is Map && item['cantidad'] is int && item['precio_unitario_centavos'] is int) {
        total += (item['cantidad'] as int) * (item['precio_unitario_centavos'] as int);
      }
    }
    return total;
  }
}
