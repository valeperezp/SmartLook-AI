import 'package:flutter/foundation.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/schema.dart';
import 'suscripcion_stock_dao.dart';

/// Caché local del catálogo (productos + stock por variante y sucursal).
///
/// Cada mapa tiene los nombres de columna de `catalogo_local` (ver `Schema`).
class CatalogoLocalDao {
  CatalogoLocalDao({AppDatabase? appDatabase}) : _appDb = appDatabase ?? AppDatabase.instance;

  final AppDatabase _appDb;

  /// Reemplaza TODO el catálogo local por [productos], en una sola transacción: si algún registro
  /// es inválido (CHECK, clave duplicada...) se revierte todo y la caché anterior queda intacta.
  ///
  /// Un lote vacío no hace nada: así una respuesta vacía por error no borra la caché que sí sirve.
  ///
  /// En la misma transacción revisa los avisos de stock pendientes (CU16): los que ahora tienen stock > 0 pasan a
  /// 'notificado'. Devuelve esos avisos para que la UI le diga al cliente "¡Llegó stock de X!".
  Future<List<Map<String, dynamic>>> guardarLoteCatalogo(List<Map<String, dynamic>> productos) async {
    final db = await _appDb.database;
    if (db == null) {
      throw UnsupportedError('El catálogo offline no está disponible en esta plataforma (web).');
    }
    if (productos.isEmpty) {
      debugPrint('[CatalogoLocalDao] Lote vacío: se conserva el catálogo local existente.');
      return const [];
    }

    try {
      final ahora = DateTime.now().toUtc().toIso8601String();
      late List<Map<String, dynamic>> avisos;
      await db.transaction((txn) async {
        await txn.delete(Schema.tablaCatalogoLocal);
        final batch = txn.batch();
        for (final producto in productos) {
          batch.insert(Schema.tablaCatalogoLocal, {'sincronizado_en': ahora, ...producto});
        }
        await batch.commit(noResult: true);
        avisos = await SuscripcionStockDao.notificarSegunCatalogoEn(txn);
      });
      debugPrint('[CatalogoLocalDao] Catálogo local reemplazado: ${productos.length} registros, ${avisos.length} avisos de stock.');
      return avisos;
    } catch (e, st) {
      debugPrint('[CatalogoLocalDao] Error al guardar el lote de catálogo: $e\n$st');
      rethrow;
    }
  }

  /// Cuándo se descargó el catálogo local por última vez (`sincronizado_en` más reciente), o null si no hay catálogo.
  /// Todas las filas se escriben juntas en cada descarga, así que comparten la misma fecha.
  Future<DateTime?> obtenerFechaUltimaDescarga() async {
    final db = await _appDb.database;
    if (db == null) return null;
    try {
      final filas = await db.rawQuery('SELECT MAX(sincronizado_en) AS fecha FROM ${Schema.tablaCatalogoLocal}');
      final texto = filas.isEmpty ? null : filas.first['fecha'] as String?;
      return texto == null ? null : DateTime.tryParse(texto);
    } catch (e, st) {
      debugPrint('[CatalogoLocalDao] Error al leer la fecha de la última descarga: $e\n$st');
      rethrow;
    }
  }

  /// Todos los registros del catálogo local (opcionalmente solo los de una sucursal).
  Future<List<Map<String, dynamic>>> obtenerProductos({int? sucursalId}) async {
    final db = await _appDb.database;
    if (db == null) return const [];

    try {
      return await db.query(
        Schema.tablaCatalogoLocal,
        where: sucursalId != null ? 'sucursal_id = ?' : null,
        whereArgs: sucursalId != null ? [sucursalId] : null,
        orderBy: 'nombre_producto, nombre_talla, nombre_color',
      );
    } catch (e, st) {
      debugPrint('[CatalogoLocalDao] Error al leer el catálogo local: $e\n$st');
      rethrow;
    }
  }
}
