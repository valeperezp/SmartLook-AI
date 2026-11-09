import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import '../../../core/database/app_database.dart';
import '../../../core/database/schema.dart';

/// Caché local (SQLite) de la imagen del QR bancario de cada sucursal.
///
/// El QR se descarga mientras hay red (al actualizar el catálogo) para poder mostrarlo SIN conexión cuando el cliente hace una
/// compra offline y paga por transferencia. Es solo una copia de lectura: la fuente de verdad es el servidor.
class QrSucursalCacheDao {
  QrSucursalCacheDao({AppDatabase? appDatabase}) : _appDb = appDatabase ?? AppDatabase.instance;

  final AppDatabase _appDb;

  /// Guarda (o reemplaza) la imagen del QR de [sucursalId].
  Future<void> guardar(int sucursalId, List<int> imagen, {String? url}) async {
    final db = await _appDb.database;
    if (db == null || imagen.isEmpty) return;
    try {
      await db.insert(
        Schema.tablaQrSucursalCache,
        {
          'sucursal_id': sucursalId,
          'imagen': Uint8List.fromList(imagen),
          'imagen_url': url,
          'actualizado_en': DateTime.now().toUtc().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e, st) {
      debugPrint('[QrSucursalCacheDao] Error al guardar el QR de la sucursal $sucursalId: $e\n$st');
      rethrow;
    }
  }

  /// La imagen guardada del QR de [sucursalId], o null si nunca se descargó.
  Future<Uint8List?> obtener(int sucursalId) async {
    final db = await _appDb.database;
    if (db == null) return null;
    final filas = await db.query(Schema.tablaQrSucursalCache, columns: ['imagen'], where: 'sucursal_id = ?', whereArgs: [sucursalId]);
    if (filas.isEmpty) return null;
    final imagen = filas.first['imagen'];
    return imagen is Uint8List ? imagen : Uint8List.fromList((imagen as List).cast<int>());
  }

  /// Borra el QR guardado (la sucursal ya no tiene uno activo).
  Future<void> eliminar(int sucursalId) async {
    final db = await _appDb.database;
    if (db == null) return;
    await db.delete(Schema.tablaQrSucursalCache, where: 'sucursal_id = ?', whereArgs: [sucursalId]);
  }
}
