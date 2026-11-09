import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/schema.dart';

/// El archivo elegido no sirve como QR: está vacío, es demasiado grande o no es una imagen PNG/JPG/WEBP.
class QrInvalido implements Exception {
  QrInvalido(this.mensaje);

  final String mensaje;

  @override
  String toString() => mensaje;
}

/// Qué pasó (en este dispositivo) con el QR que el cliente adjuntó a un pedido cancelado.
enum EstadoQrLocal {
  /// No hay nada en la cola para ese pedido (nunca se adjuntó, o ya se envió).
  ninguno,

  /// Guardado en el celular, esperando a que haya red / a que se sincronice.
  enCola,

  /// El servidor lo rechazó (p. ej. la imagen no era válida): hay que adjuntar otro.
  rechazado,
}

class QrLocal {
  const QrLocal(this.estado, {this.motivo});

  static const QrLocal ninguno = QrLocal(EstadoQrLocal.ninguno);

  final EstadoQrLocal estado;

  /// Motivo del rechazo del servidor (solo con [EstadoQrLocal.rechazado]).
  final String? motivo;
}

/// QR bancario que el cliente adjunta a un pedido cancelado para recibir su reembolso (reserva o venta).
///
/// Funciona sin conexión: el QR se guarda en `sync_queue` como SUBIR_QR_DEVOLUCION (la imagen en base64 dentro de
/// `payload_json`) y [SyncService] lo envía al servidor cuando vuelve la red. Solo hay un QR por pedido: uno nuevo reemplaza al
/// que todavía no se envió.
class QrDevolucionDao {
  QrDevolucionDao({AppDatabase? appDatabase}) : _appDb = appDatabase ?? AppDatabase.instance;

  final AppDatabase _appDb;
  static const _uuid = Uuid();

  /// Mismo límite que el servidor (5 MB): un QR bancario pesa mucho menos.
  static const int maxBytes = 5 * 1024 * 1024;

  /// Clave con la que se identifica un pedido en [estados].
  static String clavePedido({int? reservaId, int? ventaId}) => reservaId != null ? 'reserva:$reservaId' : 'venta:$ventaId';

  /// Valida el archivo como lo hace el servidor: por su CONTENIDO (firma PNG/JPEG/WEBP), no por la extensión.
  static void validarImagen(List<int> bytes) {
    if (bytes.isEmpty) throw QrInvalido('La imagen está vacía.');
    if (bytes.length > maxBytes) throw QrInvalido('La imagen supera los ${maxBytes ~/ (1024 * 1024)} MB.');
    final png = bytes.length >= 8 && _empiezaCon(bytes, const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
    final jpg = bytes.length >= 3 && _empiezaCon(bytes, const [0xFF, 0xD8, 0xFF]);
    final webp = bytes.length >= 12 && _empiezaCon(bytes, const [0x52, 0x49, 0x46, 0x46]) && _empiezaCon(bytes.sublist(8), const [0x57, 0x45, 0x42, 0x50]);
    if (!png && !jpg && !webp) throw QrInvalido('El archivo no es una imagen válida. Usa PNG, JPG o WEBP.');
  }

  static bool _empiezaCon(List<int> bytes, List<int> firma) {
    for (var i = 0; i < firma.length; i++) {
      if (bytes[i] != firma[i]) return false;
    }
    return true;
  }

  /// Guarda el QR en la cola de sincronización (reemplaza uno anterior del mismo pedido que siga sin enviarse). Una sola
  /// transacción. Devuelve el id de la entrada de la cola. Lanza [QrInvalido] si la imagen no sirve.
  Future<String> encolar({int? reservaId, int? ventaId, required List<int> imagen, String nombreArchivo = 'qr.jpg'}) async {
    if ((reservaId == null) == (ventaId == null)) throw ArgumentError('Indica la reserva o la venta (solo una de las dos)');
    validarImagen(imagen);
    final db = await _appDb.database;
    if (db == null) throw UnsupportedError('Las operaciones offline no están disponibles en esta plataforma (web).');

    final colaId = _uuid.v4();
    try {
      await db.transaction((txn) async {
        final previos = await txn.query(
          Schema.tablaSyncQueue,
          columns: ['id', 'payload_json'],
          where: "tipo_operacion = ? AND estado IN ('pendiente', 'error', 'rechazado')",
          whereArgs: [Schema.tipoSubirQrDevolucion],
        );
        for (final previo in previos) {
          final p = jsonDecode(previo['payload_json'] as String) as Map<String, dynamic>;
          if (p['reserva_id'] == reservaId && p['venta_id'] == ventaId) {
            await txn.delete(Schema.tablaSyncQueue, where: 'id = ?', whereArgs: [previo['id']]);
          }
        }
        await txn.insert(Schema.tablaSyncQueue, {
          'id': colaId,
          'tipo_operacion': Schema.tipoSubirQrDevolucion,
          'payload_json': jsonEncode({
            'reserva_id': ?reservaId,
            'venta_id': ?ventaId,
            'nombre_archivo': nombreArchivo,
            'imagen_base64': base64Encode(imagen),
          }),
          'estado': Schema.estadoPendiente,
          'intentos': 0,
          'fecha_creacion': DateTime.now().toUtc().toIso8601String(),
        });
      });
    } catch (e, st) {
      debugPrint('[QrDevolucionDao] Error al guardar el QR en la cola: $e\n$st');
      rethrow;
    }
    debugPrint('[QrDevolucionDao] QR de ${clavePedido(reservaId: reservaId, ventaId: ventaId)} encolado ($colaId).');
    return colaId;
  }

  /// Estado local del QR de cada pedido que tiene algo en la cola (los ya enviados no aparecen). La clave es
  /// [clavePedido]. Si un pedido tiene varias entradas gana la más reciente.
  Future<Map<String, QrLocal>> estados() async {
    final db = await _appDb.database;
    if (db == null) return {};
    try {
      final filas = await db.query(
        Schema.tablaSyncQueue,
        columns: ['payload_json', 'estado', 'ultimo_error'],
        where: "tipo_operacion = ? AND estado IN ('pendiente', 'en_proceso', 'error', 'rechazado')",
        whereArgs: [Schema.tipoSubirQrDevolucion],
        orderBy: 'fecha_creacion ASC, rowid ASC',
      );
      final mapa = <String, QrLocal>{};
      for (final fila in filas) {
        final p = jsonDecode(fila['payload_json'] as String) as Map<String, dynamic>;
        final clave = clavePedido(reservaId: p['reserva_id'] as int?, ventaId: p['venta_id'] as int?);
        mapa[clave] = fila['estado'] == 'rechazado'
            ? QrLocal(EstadoQrLocal.rechazado, motivo: fila['ultimo_error'] as String?)
            : const QrLocal(EstadoQrLocal.enCola);
      }
      return mapa;
    } catch (e, st) {
      debugPrint('[QrDevolucionDao] Error al leer los QR en cola: $e\n$st');
      rethrow;
    }
  }

  /// El servidor guardó el QR: la entrada pasa a 'sincronizado' y se descarta la imagen (ya no hace falta guardarla dos veces).
  Future<void> marcarSincronizado(String colaId) => _cerrar(colaId, estado: 'sincronizado', motivo: null);

  /// El servidor rechazó el QR (imagen inválida, pedido que ya no admite reembolso...): queda 'rechazado' con el [motivo]. No se
  /// reintenta; el cliente tiene que adjuntar otro.
  Future<void> marcarRechazado(String colaId, String motivo) => _cerrar(colaId, estado: 'rechazado', motivo: motivo);

  Future<void> _cerrar(String colaId, {required String estado, required String? motivo}) async {
    final db = await _appDb.database;
    if (db == null) throw UnsupportedError('Las operaciones offline no están disponibles en esta plataforma (web).');
    try {
      await db.transaction((txn) async {
        // Solo se cierra lo que sigue abierto: una entrada ya sincronizada/rechazada no se pisa.
        final fila = await txn.query(
          Schema.tablaSyncQueue,
          columns: ['payload_json'],
          where: "id = ? AND tipo_operacion = ? AND estado IN ('pendiente', 'en_proceso')",
          whereArgs: [colaId, Schema.tipoSubirQrDevolucion],
        );
        if (fila.length != 1) throw StateError('El QR $colaId no está pendiente de sincronizar.');
        final payload = (jsonDecode(fila.first['payload_json'] as String) as Map<String, dynamic>)..remove('imagen_base64');
        await txn.update(
          Schema.tablaSyncQueue,
          {
            'estado': estado,
            'ultimo_error': motivo,
            'fecha_ultimo_intento': DateTime.now().toUtc().toIso8601String(),
            'payload_json': jsonEncode(payload),
          },
          where: 'id = ?',
          whereArgs: [colaId],
        );
      });
    } catch (e, st) {
      debugPrint('[QrDevolucionDao] Error al cerrar el QR $colaId como $estado: $e\n$st');
      rethrow;
    }
  }
}
