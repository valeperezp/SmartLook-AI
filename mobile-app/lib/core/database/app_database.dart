import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'schema.dart';

/// Acceso único a la base SQLite local (módulo offline).
///
/// sqflite no soporta web: con `kIsWeb` [database] devuelve `null` y no se abre nada.
class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  /// Solo para pruebas: usa una base ya abierta (p. ej. en memoria con sqflite_common_ffi).
  @visibleForTesting
  AppDatabase.conBaseDeDatos(Database db) : _dbFuture = Future.value(db);

  /// Se guarda el Future (no el Database) para que dos llamadas simultáneas no abran la base dos veces.
  Future<Database>? _dbFuture;

  static bool get soportado => !kIsWeb;

  /// Base abierta, o `null` si la plataforma no está soportada (web).
  Future<Database?> get database async {
    if (kIsWeb) {
      debugPrint('[AppDatabase] SQLite no está soportado en web: módulo offline desactivado.');
      return null;
    }
    try {
      return await (_dbFuture ??= _abrirPorDefecto());
    } catch (e, st) {
      _dbFuture = null; // permite reintentar en la próxima llamada
      debugPrint('[AppDatabase] No se pudo abrir la base local: $e\n$st');
      rethrow;
    }
  }

  Future<Database> _abrirPorDefecto() async {
    final carpeta = await getDatabasesPath();
    return abrir(p.join(carpeta, Schema.nombreArchivo));
  }

  /// Abre (y crea si hace falta) la base en [ruta] con la configuración del proyecto.
  static Future<Database> abrir(String ruta) {
    return openDatabase(
      ruta,
      version: Schema.version,
      // SQLite trae las claves foráneas DESACTIVADAS por defecto: sin esto no hay integridad referencial.
      // Excepción: al migrar de una versión anterior se dejan DESACTIVADAS (reconstruir una tabla padre con ellas
      // activas borraría en cascada sus hijos); `onOpen` las reactiva siempre, ya fuera de la transacción.
      onConfigure: (db) async {
        final versionActual = Sqflite.firstIntValue(await db.rawQuery('PRAGMA user_version')) ?? 0;
        final migrando = versionActual > 0 && versionActual < Schema.version;
        await db.execute('PRAGMA foreign_keys = ${migrando ? 'OFF' : 'ON'}');
      },
      onOpen: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        for (final sentencia in Schema.ddl) {
          await db.execute(sentencia);
        }
        debugPrint('[AppDatabase] Esquema v$version creado.');
      },
      // Se corre dentro de una transacción: si una sentencia falla, la base queda en su versión anterior.
      onUpgrade: (db, anterior, nueva) async {
        if (anterior < 2) {
          for (final sentencia in Schema.migracionV2) {
            await db.execute(sentencia);
          }
        }
        if (anterior < 3) {
          for (final sentencia in Schema.migracionV3) {
            await db.execute(sentencia);
          }
        }
        if (anterior < 4) {
          for (final sentencia in Schema.migracionV4) {
            await db.execute(sentencia);
          }
        }
        if (anterior < 5) {
          for (final sentencia in Schema.migracionV5) {
            await db.execute(sentencia);
          }
          // Con las claves foráneas desactivadas nada las vigiló: se comprueba antes de confirmar (si falla, se revierte todo).
          final violaciones = await db.rawQuery('PRAGMA foreign_key_check');
          if (violaciones.isNotEmpty) {
            throw StateError('La migración a v5 dejó ${violaciones.length} claves foráneas rotas: $violaciones');
          }
        }
        debugPrint('[AppDatabase] Esquema migrado de v$anterior a v$nueva.');
      },
    );
  }

  Future<void> cerrar() async {
    final futuro = _dbFuture;
    _dbFuture = null;
    if (futuro == null) return;
    try {
      await (await futuro).close();
    } catch (e) {
      debugPrint('[AppDatabase] Error al cerrar la base: $e');
    }
  }
}
