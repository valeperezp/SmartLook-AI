import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart' show Database, DatabaseException, DatabaseExecutor;
import 'package:uuid/uuid.dart';

import '../../../core/config/offline_config.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/schema.dart';

/// Resultado de [SuscripcionStockDao.crearSuscripcion].
class ResultadoSuscripcion {
  const ResultadoSuscripcion({required this.id, required this.creada});

  final String id;

  /// `false` si el cliente ya tenía un aviso pendiente para esa variante (se devuelve el existente).
  final bool creada;
}

/// Avisos de "Avísame cuando llegue" de un producto agotado (CU16).
///
/// Un aviso queda 'pendiente' hasta que el catálogo local se refresca y esa variante tiene stock: entonces pasa a
/// 'notificado' (y `visto = 0` hasta que la UI se lo muestre al cliente). Si pasan [OfflineConfig.vigenciaSuscripcionDias]
/// días sin novedad, pasa a 'expirado'.
class SuscripcionStockDao {
  SuscripcionStockDao({AppDatabase? appDatabase}) : _appDb = appDatabase ?? AppDatabase.instance;

  final AppDatabase _appDb;
  static const _uuid = Uuid();

  Future<Database> _db() async {
    final db = await _appDb.database;
    if (db == null) {
      throw UnsupportedError('Los avisos de stock offline no están disponibles en esta plataforma (web).');
    }
    return db;
  }

  /// Suscribe al cliente a una variante agotada. Si ya tiene un aviso pendiente para la misma variante y sucursal
  /// no crea otro: devuelve el existente. [descripcion] es el texto que verá el cliente ("Camiseta · M · Blanco").
  Future<ResultadoSuscripcion> crearSuscripcion({
    required int clienteId,
    required int productoId,
    int? tallaId,
    int? colorId,
    int? sucursalId,
    required String descripcion,
  }) async {
    final db = await _db();
    try {
      return await db.transaction((txn) async {
        final existente = await _pendiente(txn, clienteId, productoId, tallaId, colorId, sucursalId);
        if (existente != null) return ResultadoSuscripcion(id: existente, creada: false);
        final id = _uuid.v4();
        await txn.insert(Schema.tablaSuscripcionesStock, {
          'id': id,
          'cliente_id': clienteId,
          'producto_id': productoId,
          'talla_id': tallaId,
          'color_id': colorId,
          'sucursal_id': sucursalId,
          'descripcion': descripcion,
          'fecha_suscripcion': DateTime.now().toUtc().toIso8601String(),
        });
        return ResultadoSuscripcion(id: id, creada: true);
      });
    } on DatabaseException catch (e, st) {
      // Dos pulsaciones seguidas: la segunda choca con el índice único parcial → ya existe
      if (e.isUniqueConstraintError()) {
        final existente = await _pendiente(db, clienteId, productoId, tallaId, colorId, sucursalId);
        if (existente != null) return ResultadoSuscripcion(id: existente, creada: false);
      }
      debugPrint('[SuscripcionStockDao] Error al crear la suscripción: $e\n$st');
      rethrow;
    } catch (e, st) {
      debugPrint('[SuscripcionStockDao] Error al crear la suscripción: $e\n$st');
      rethrow;
    }
  }

  /// Avisos pendientes del cliente (más recientes primero).
  Future<List<Map<String, dynamic>>> obtenerSuscripcionesPendientes(int clienteId) async {
    final db = await _appDb.database;
    if (db == null) return const [];
    try {
      return await db.query(
        Schema.tablaSuscripcionesStock,
        where: "cliente_id = ? AND estado = 'pendiente'",
        whereArgs: [clienteId],
        orderBy: 'fecha_suscripcion DESC, rowid DESC',
      );
    } catch (e, st) {
      debugPrint('[SuscripcionStockDao] Error al leer las suscripciones de $clienteId: $e\n$st');
      rethrow;
    }
  }

  /// Avisos que ya se cumplieron (hay stock) y que el cliente todavía no vio.
  Future<List<Map<String, dynamic>>> obtenerAvisosSinVer(int clienteId) async {
    final db = await _appDb.database;
    if (db == null) return const [];
    try {
      return await db.query(
        Schema.tablaSuscripcionesStock,
        where: "cliente_id = ? AND estado = 'notificado' AND visto = 0",
        whereArgs: [clienteId],
        orderBy: 'fecha_notificacion, rowid',
      );
    } catch (e, st) {
      debugPrint('[SuscripcionStockDao] Error al leer los avisos de $clienteId: $e\n$st');
      rethrow;
    }
  }

  Future<void> marcarVistos(List<String> ids) async {
    if (ids.isEmpty) return;
    final db = await _db();
    try {
      await db.transaction((txn) async {
        for (final id in ids) {
          await txn.update(Schema.tablaSuscripcionesStock, {'visto': 1}, where: 'id = ?', whereArgs: [id]);
        }
      });
    } catch (e, st) {
      debugPrint('[SuscripcionStockDao] Error al marcar avisos como vistos: $e\n$st');
      rethrow;
    }
  }

  /// El cliente ya no quiere el aviso: queda 'expirado'. Devuelve si había uno pendiente con ese id.
  Future<bool> cancelar(String id) async {
    final db = await _db();
    try {
      final filas = await db.update(
        Schema.tablaSuscripcionesStock,
        {'estado': Schema.suscripcionExpirado},
        where: "id = ? AND estado = 'pendiente'",
        whereArgs: [id],
      );
      return filas == 1;
    } catch (e, st) {
      debugPrint('[SuscripcionStockDao] Error al cancelar la suscripción $id: $e\n$st');
      rethrow;
    }
  }

  /// Pasa a 'expirado' los avisos pendientes con más de [dias] días. Devuelve cuántos.
  Future<int> expirarAntiguas({int dias = OfflineConfig.vigenciaSuscripcionDias, DateTime? ahora}) async {
    final db = await _db();
    try {
      final limite = (ahora ?? DateTime.now()).toUtc().subtract(Duration(days: dias)).toIso8601String();
      return await db.update(
        Schema.tablaSuscripcionesStock,
        {'estado': Schema.suscripcionExpirado},
        where: "estado = 'pendiente' AND fecha_suscripcion < ?",
        whereArgs: [limite],
      );
    } catch (e, st) {
      debugPrint('[SuscripcionStockDao] Error al expirar avisos: $e\n$st');
      rethrow;
    }
  }

  /// Marca como 'notificado' los avisos pendientes de esa variante y sucursal (cuando se sabe que llegó stock).
  /// Una suscripción sin talla/color/sucursal (null) vale para cualquiera. Devuelve los avisos que cambiaron.
  Future<List<Map<String, dynamic>>> marcarNotificadas(int productoId, int? tallaId, int? colorId, int? sucursalId) async {
    final db = await _db();
    try {
      return await db.transaction((txn) async {
        final filas = await txn.query(
          Schema.tablaSuscripcionesStock,
          where: "estado = 'pendiente' AND producto_id = ? "
              'AND (talla_id IS NULL OR ? IS NULL OR talla_id = ?) '
              'AND (color_id IS NULL OR ? IS NULL OR color_id = ?) '
              'AND (sucursal_id IS NULL OR ? IS NULL OR sucursal_id = ?)',
          whereArgs: [productoId, tallaId, tallaId, colorId, colorId, sucursalId, sucursalId],
        );
        return _notificar(txn, filas);
      });
    } catch (e, st) {
      debugPrint('[SuscripcionStockDao] Error al marcar notificadas: $e\n$st');
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Sincronización con el servidor (CU16): la tabla es su propia cola de envío
  // ---------------------------------------------------------------------------

  /// Avisos que se hicieron (quizá sin conexión) y todavía no llegaron al servidor: se envían con su `id` como uuid.
  Future<List<Map<String, dynamic>>> obtenerPorEnviar(int clienteId) async {
    final db = await _db();
    return db.query(
      Schema.tablaSuscripcionesStock,
      where: "cliente_id = ? AND estado = 'pendiente' AND sync_estado = 'pendiente'",
      whereArgs: [clienteId],
      orderBy: 'fecha_suscripcion, rowid',
    );
  }

  /// El servidor guardó el aviso: queda 'sincronizado' con el id que le dio.
  Future<void> marcarEnviada(String id, int idServidor) async {
    final db = await _db();
    await db.update(Schema.tablaSuscripcionesStock, {'sync_estado': 'sincronizado', 'id_servidor': idServidor}, where: 'id = ?', whereArgs: [id]);
  }

  /// El servidor rechazó el aviso (p. ej. el producto ya no existe): no se reintenta.
  Future<void> marcarRechazadaPorServidor(String id) async {
    final db = await _db();
    await db.update(Schema.tablaSuscripcionesStock, {'sync_estado': 'rechazado'}, where: 'id = ?', whereArgs: [id]);
  }

  /// Aplica los avisos que informa el servidor (`GET /suscripciones/mis-notificaciones`): los que esperaba este dispositivo pasan a
  /// 'notificado' y los que se pidieron desde otro dispositivo o desde la web se agregan ya notificados. Devuelve cuántos avisos
  /// NUEVOS (que el cliente aún no vio) quedaron en el dispositivo.
  Future<int> aplicarNotificacionesDelServidor(int clienteId, List<Map<String, dynamic>> servidor) async {
    if (servidor.isEmpty) return 0;
    final db = await _db();
    try {
      return await db.transaction((txn) async {
        var nuevos = 0;
        for (final s in servidor) {
          final idServidor = s['id'] as int?;
          final uuid = s['uuid'] as String?;
          final vistoEnServidor = s['visto'] == true;
          final locales = await txn.query(
            Schema.tablaSuscripcionesStock,
            where: 'cliente_id = ? AND (id_servidor = ? OR id = ?)',
            whereArgs: [clienteId, idServidor, uuid ?? '\u0000'],
            limit: 1,
          );
          final ahora = (s['notificado_en'] as String?) ?? DateTime.now().toUtc().toIso8601String();
          if (locales.isEmpty) {
            // Se pidió desde otro dispositivo o desde la web: se agrega ya notificada
            await txn.insert(Schema.tablaSuscripcionesStock, {
              'id': uuid ?? 'srv-$idServidor',
              'cliente_id': clienteId,
              'producto_id': s['producto_id'],
              'talla_id': s['talla_id'],
              'color_id': s['color_id'],
              'sucursal_id': s['sucursal_id'],
              'descripcion': (s['descripcion'] as String?) ?? (s['nombre_producto'] as String? ?? 'Producto'),
              'fecha_suscripcion': (s['fecha'] as String?) ?? ahora,
              'estado': Schema.suscripcionNotificado,
              'fecha_notificacion': ahora,
              'visto': vistoEnServidor ? 1 : 0,
              'sync_estado': 'sincronizado',
              'id_servidor': idServidor,
            });
            if (!vistoEnServidor) nuevos++;
            continue;
          }
          final local = locales.first;
          if (local['id_servidor'] == null && idServidor != null) {
            await txn.update(Schema.tablaSuscripcionesStock, {'sync_estado': 'sincronizado', 'id_servidor': idServidor}, where: 'id = ?', whereArgs: [local['id']]);
          }
          if (local['estado'] == 'pendiente') {
            await txn.update(
              Schema.tablaSuscripcionesStock,
              {'estado': Schema.suscripcionNotificado, 'fecha_notificacion': ahora, 'visto': vistoEnServidor ? 1 : 0},
              where: 'id = ?',
              whereArgs: [local['id']],
            );
            if (!vistoEnServidor) nuevos++;
          }
        }
        return nuevos;
      });
    } catch (e, st) {
      debugPrint('[SuscripcionStockDao] Error al aplicar las notificaciones del servidor: $e\n$st');
      rethrow;
    }
  }

  /// Gancho del refresco de catálogo: notifica los avisos pendientes cuya variante aparece ahora con stock > 0 en
  /// `catalogo_local`. Corre dentro de la transacción que guardó el catálogo. Devuelve los avisos notificados.
  static Future<List<Map<String, dynamic>>> notificarSegunCatalogoEn(DatabaseExecutor txn) async {
    final filas = await txn.rawQuery(
      'SELECT s.* FROM ${Schema.tablaSuscripcionesStock} s '
      "WHERE s.estado = 'pendiente' AND EXISTS ("
      ' SELECT 1 FROM ${Schema.tablaCatalogoLocal} c WHERE c.producto_id = s.producto_id'
      '  AND c.cantidad_disponible > 0 AND c.activo = 1'
      '  AND (s.sucursal_id IS NULL OR c.sucursal_id = s.sucursal_id)'
      '  AND (s.talla_id IS NULL OR c.talla_id = s.talla_id)'
      '  AND (s.color_id IS NULL OR c.color_id = s.color_id))',
    );
    return _notificar(txn, filas);
  }

  // ---------------------------------------------------------------------------

  static Future<List<Map<String, dynamic>>> _notificar(DatabaseExecutor txn, List<Map<String, Object?>> filas) async {
    if (filas.isEmpty) return const [];
    final ahora = DateTime.now().toUtc().toIso8601String();
    for (final f in filas) {
      await txn.update(
        Schema.tablaSuscripcionesStock,
        {'estado': Schema.suscripcionNotificado, 'fecha_notificacion': ahora, 'visto': 0},
        where: 'id = ?',
        whereArgs: [f['id']],
      );
    }
    return [for (final f in filas) {...f, 'estado': Schema.suscripcionNotificado, 'fecha_notificacion': ahora}];
  }

  static Future<String?> _pendiente(
    DatabaseExecutor ex,
    int clienteId,
    int productoId,
    int? tallaId,
    int? colorId,
    int? sucursalId,
  ) async {
    final filas = await ex.query(
      Schema.tablaSuscripcionesStock,
      columns: ['id'],
      where: "estado = 'pendiente' AND cliente_id = ? AND producto_id = ? AND IFNULL(talla_id, 0) = IFNULL(?, 0) "
          'AND IFNULL(color_id, 0) = IFNULL(?, 0) AND IFNULL(sucursal_id, 0) = IFNULL(?, 0)',
      whereArgs: [clienteId, productoId, tallaId, colorId, sucursalId],
    );
    return filas.isEmpty ? null : filas.first['id'] as String;
  }
}
