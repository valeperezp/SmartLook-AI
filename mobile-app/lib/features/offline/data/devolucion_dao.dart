import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart' show Database, DatabaseExecutor, Transaction;
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/schema.dart';
import 'puntos_dao.dart';
import 'sync_queue_dao.dart' show StockLocalInsuficiente;
import 'turno_caja_dao.dart' show TurnoNoAbierto;

/// La venta original no admite cambios/devoluciones (no existe, fue rechazada, otra sucursal, plazo vencido...).
class VentaNoDevolvible implements Exception {
  VentaNoDevolvible(this.motivo);

  final String motivo;

  @override
  String toString() => motivo;
}

/// Se quiere devolver más unidades de las que se vendieron (descontando lo ya devuelto antes).
class CantidadDevolucionExcedida implements Exception {
  CantidadDevolucionExcedida(this.producto, this.maximo);

  final String producto;
  final int maximo;

  @override
  String toString() => 'De "$producto" solo se pueden devolver $maximo unidad(es).';
}

/// La prenda nueva no está en el catálogo local de la sucursal.
class PrendaNoDisponible implements Exception {
  PrendaNoDisponible(this.detalle);

  final String detalle;

  @override
  String toString() => detalle;
}

/// Lo que dejó registrar un cambio/devolución. `diferencia = nuevo - devuelto`:
/// positiva → el cliente paga la diferencia; negativa → la tienda le devuelve dinero.
class ResultadoDevolucion {
  const ResultadoDevolucion({required this.id, required this.totalDevueltoCentavos, required this.totalNuevoCentavos});

  final String id;
  final int totalDevueltoCentavos;
  final int totalNuevoCentavos;

  int get diferenciaCentavos => totalNuevoCentavos - totalDevueltoCentavos;
}

/// Cambios y devoluciones de ventas de contado, hechos sin conexión (CU11).
///
/// Cada registro, en UNA transacción: valida la venta original y el turno abierto, guarda la devolución con sus
/// ítems, SUMA el stock de lo devuelto, RESTA el de lo nuevo y deja un 'DEVOLUCION' en `sync_queue`.
/// Lo devuelto se reembolsa al precio de la venta original; lo nuevo se cobra al precio del catálogo local.
/// La diferencia en efectivo (nuevo - devuelto) la incluye el arqueo del turno.
class DevolucionDao {
  DevolucionDao({AppDatabase? appDatabase, this.plazoDias = 7}) : _appDb = appDatabase ?? AppDatabase.instance;

  final AppDatabase _appDb;

  /// Días, desde la venta, dentro de los cuales se admite un cambio o devolución.
  final int plazoDias;
  static const _uuid = Uuid();

  Future<Database> _db() async {
    final db = await _appDb.database;
    if (db == null) {
      throw UnsupportedError('Los cambios y devoluciones offline no están disponibles en esta plataforma (web).');
    }
    return db;
  }

  static String _clave(Object? productoId, Object? tallaId, Object? colorId) =>
      '$productoId|${tallaId ?? 0}|${colorId ?? 0}';

  // ---------------------------------------------------------------------------
  // Registro
  // ---------------------------------------------------------------------------

  /// [itemsDevueltos] y [itemsNuevos]: listas de `{producto_id, talla_id?, color_id?, cantidad}`. El precio y el
  /// nombre los pone el DAO (de la venta original y del catálogo local), nunca el llamador.
  ///
  /// Errores: [TurnoNoAbierto], [VentaNoDevolvible], [CantidadDevolucionExcedida], [PrendaNoDisponible],
  /// [StockLocalInsuficiente] y `ArgumentError` por datos mal formados. Ante cualquiera no se guarda nada.
  Future<ResultadoDevolucion> registrarDevolucion(
    String ventaUuid,
    String tipo,
    List<Map<String, dynamic>> itemsDevueltos,
    List<Map<String, dynamic>> itemsNuevos,
    String turnoUuid, {
    String? motivo,
    DateTime? ahora,
  }) async {
    final db = await _db();
    try {
      _validarForma(tipo, itemsDevueltos, itemsNuevos);
      final ahoraUtc = (ahora ?? DateTime.now()).toUtc();
      late ResultadoDevolucion resultado;

      await db.transaction((Transaction txn) async {
        // 1. Turno abierto (sin caja no se sabe a qué efectivo afectar)
        final turnos = await txn.query(Schema.tablaTurnosCaja, where: 'id = ?', whereArgs: [turnoUuid]);
        if (turnos.isEmpty || turnos.first['estado'] != Schema.turnoAbierto) throw TurnoNoAbierto(turnoUuid);
        final turno = turnos.first;
        final sucursalId = turno['sucursal_id'] as int;

        // 2. Venta original
        final venta = await _validarVenta(txn, ventaUuid, sucursalId, ahoraUtc);
        final vendidas = await _itemsDeLaVenta(txn, ventaUuid);
        final yaDevueltas = await _cantidadesYaDevueltas(txn, ventaUuid);

        // 3. Lo que vuelve: solo prendas de esa venta, a su precio original, sin pasarse de lo vendido
        final devueltos = <Map<String, Object?>>[];
        var totalDevuelto = 0;
        for (final e in _agrupar(itemsDevueltos).entries) {
          final linea = vendidas[e.key];
          if (linea == null) throw VentaNoDevolvible('Una de las prendas no pertenece a la venta original.');
          final maximo = (linea['cantidad'] as int) - (yaDevueltas[e.key] ?? 0);
          if (e.value.cantidad > maximo) throw CantidadDevolucionExcedida(linea['nombre_producto'] as String, maximo < 0 ? 0 : maximo);
          final precio = linea['precio_unitario_centavos'] as int;
          totalDevuelto += precio * e.value.cantidad;
          devueltos.add({
            'producto_id': linea['producto_id'],
            'talla_id': linea['talla_id'],
            'color_id': linea['color_id'],
            'nombre_producto': linea['nombre_producto'],
            'cantidad': e.value.cantidad,
            'precio_centavos': precio,
            'tipo_item': Schema.itemDevuelto,
          });
        }

        // 4. Lo que vuelve a la estantería (primero, así un cambio por la misma prenda no choca con stock 0)
        for (final d in devueltos) {
          await txn.rawUpdate(
            'UPDATE ${Schema.tablaCatalogoLocal} SET cantidad_disponible = cantidad_disponible + ? '
            'WHERE sucursal_id = ? AND producto_id = ? AND IFNULL(talla_id, 0) = IFNULL(?, 0) '
            'AND IFNULL(color_id, 0) = IFNULL(?, 0)',
            [d['cantidad'], sucursalId, d['producto_id'], d['talla_id'], d['color_id']],
          );
        }

        // 5. Lo que se lleva: precio y existencias del catálogo local
        final nuevos = <Map<String, Object?>>[];
        var totalNuevo = 0;
        for (final e in _agrupar(itemsNuevos).entries) {
          final filas = await txn.query(
            Schema.tablaCatalogoLocal,
            where: 'sucursal_id = ? AND producto_id = ? AND IFNULL(talla_id, 0) = IFNULL(?, 0) '
                'AND IFNULL(color_id, 0) = IFNULL(?, 0) AND activo = 1',
            whereArgs: [sucursalId, e.value.productoId, e.value.tallaId, e.value.colorId],
          );
          if (filas.isEmpty) throw PrendaNoDisponible('Una de las prendas nuevas no está en el catálogo de esta sucursal.');
          final item = filas.first;
          final actualizadas = await txn.rawUpdate(
            'UPDATE ${Schema.tablaCatalogoLocal} SET cantidad_disponible = cantidad_disponible - ? '
            'WHERE inventario_id = ? AND cantidad_disponible >= ?',
            [e.value.cantidad, item['inventario_id'], e.value.cantidad],
          );
          if (actualizadas != 1) throw StockLocalInsuficiente(item['inventario_id'] as int);
          final precio = item['precio_centavos'] as int;
          totalNuevo += precio * e.value.cantidad;
          nuevos.add({
            'producto_id': item['producto_id'],
            'talla_id': item['talla_id'],
            'color_id': item['color_id'],
            'nombre_producto': item['nombre_producto'],
            'cantidad': e.value.cantidad,
            'precio_centavos': precio,
            'tipo_item': Schema.itemNuevo,
          });
        }

        // 6. Registro + ítems + cola
        final id = _uuid.v4();
        final fecha = ahoraUtc.toIso8601String();
        await txn.insert(Schema.tablaDevoluciones, {
          'id': id,
          'venta_uuid': ventaUuid,
          'tipo': tipo,
          'motivo': (motivo?.trim().isEmpty ?? true) ? null : motivo!.trim(),
          'cajero_id': turno['cajero_id'],
          'sucursal_id': sucursalId,
          'total_devuelto_centavos': totalDevuelto,
          'total_nuevo_centavos': totalNuevo,
          'fecha': fecha,
          'turno_uuid': turnoUuid,
        });
        final batch = txn.batch();
        for (final item in [...devueltos, ...nuevos]) {
          batch.insert(Schema.tablaDevolucionesItems, {'devolucion_id': id, ...item});
        }
        await batch.commit(noResult: true);
        await txn.insert(Schema.tablaSyncQueue, {
          'id': _uuid.v4(),
          'tipo_operacion': Schema.tipoOperacionDevolucion,
          'devolucion_id': id,
          'payload_json': jsonEncode({
            'devolucion_id': id,
            'venta_uuid': ventaUuid,
            'tipo': tipo,
            'motivo': motivo,
            'fecha': fecha,
            'turno_uuid': turnoUuid,
            'cajero_id': turno['cajero_id'],
            'sucursal_id': sucursalId,
            'total_devuelto_centavos': totalDevuelto,
            'total_nuevo_centavos': totalNuevo,
            'diferencia_centavos': totalNuevo - totalDevuelto,
            'items_devueltos': [for (final d in devueltos) _paraServidor(d)],
            'items_nuevos': [for (final n in nuevos) _paraServidor(n)],
            'venta_fecha': venta['fecha'],
          }),
          'estado': Schema.estadoPendiente,
          'intentos': 0,
          'fecha_creacion': fecha,
        });
        // Fidelización (CU17): lo devuelto le quita al cliente de la venta los puntos proporcionales
        final clienteId = venta['cliente_id'] as int?;
        if (clienteId != null) {
          await PuntosDao.restarEn(
            txn,
            clienteId: clienteId,
            ventaUuid: ventaUuid,
            origenUuid: id,
            totalVentaCentavos: venta['total_centavos'] as int,
            devueltoAcumuladoCentavos: await PuntosDao.devueltoEnDevoluciones(txn, ventaUuid),
          );
        }
        resultado = ResultadoDevolucion(id: id, totalDevueltoCentavos: totalDevuelto, totalNuevoCentavos: totalNuevo);
      });

      debugPrint('[DevolucionDao] $tipo ${resultado.id} registrada (diferencia ${resultado.diferenciaCentavos} centavos).');
      return resultado;
    } catch (e, st) {
      final esperado = e is TurnoNoAbierto ||
          e is VentaNoDevolvible ||
          e is CantidadDevolucionExcedida ||
          e is PrendaNoDisponible ||
          e is StockLocalInsuficiente;
      if (!esperado) debugPrint('[DevolucionDao] Error al registrar la devolución de $ventaUuid: $e\n$st');
      rethrow;
    }
  }

  static Map<String, Object?> _paraServidor(Map<String, Object?> i) => {
        'producto_id': i['producto_id'],
        'talla_id': i['talla_id'],
        'color_id': i['color_id'],
        'cantidad': i['cantidad'],
        'precio_centavos': i['precio_centavos'],
      };

  void _validarForma(String tipo, List<Map<String, dynamic>> devueltos, List<Map<String, dynamic>> nuevos) {
    if (tipo != Schema.devolucionCambio && tipo != Schema.devolucionSoloDevolucion) {
      throw ArgumentError('tipo inválido: $tipo (usar CAMBIO o DEVOLUCION)');
    }
    if (devueltos.isEmpty) throw ArgumentError('Hay que devolver al menos una prenda');
    if (tipo == Schema.devolucionSoloDevolucion && nuevos.isNotEmpty) {
      throw ArgumentError('Una DEVOLUCION no lleva prendas nuevas (eso es un CAMBIO)');
    }
    if (tipo == Schema.devolucionCambio && nuevos.isEmpty) {
      throw ArgumentError('Un CAMBIO necesita al menos una prenda nueva');
    }
  }

  /// Agrupa por variante sumando cantidades; valida la forma de cada ítem.
  Map<String, _Linea> _agrupar(List<Map<String, dynamic>> items) {
    final r = <String, _Linea>{};
    for (final (i, item) in items.indexed) {
      final producto = item['producto_id'];
      final cantidad = item['cantidad'];
      final talla = item['talla_id'];
      final color = item['color_id'];
      if (producto is! int || cantidad is! int || cantidad <= 0 || (talla != null && talla is! int) || (color != null && color is! int)) {
        throw ArgumentError('items[$i] inválido: requiere producto_id y cantidad (> 0) enteros');
      }
      final k = _clave(producto, talla, color);
      final previo = r[k];
      r[k] = _Linea(producto, talla as int?, color as int?, (previo?.cantidad ?? 0) + cantidad);
    }
    return r;
  }

  Future<Map<String, Object?>> _validarVenta(DatabaseExecutor ex, String ventaUuid, int sucursalId, DateTime ahora) async {
    final filas = await ex.query(Schema.tablaOperaciones, where: 'uuid = ?', whereArgs: [ventaUuid]);
    if (filas.isEmpty) throw VentaNoDevolvible('La venta no existe en este dispositivo.');
    final venta = filas.first;
    if (venta['tipo_operacion'] != Schema.tipoVentaContado) {
      throw VentaNoDevolvible('Solo se admiten cambios y devoluciones de ventas de contado.');
    }
    if (venta['estado'] == 'rechazada') throw VentaNoDevolvible('La venta fue rechazada por el servidor.');
    if (venta['sucursal_id'] != sucursalId) throw VentaNoDevolvible('La venta es de otra sucursal.');
    final fecha = DateTime.parse(venta['fecha'] as String);
    if (ahora.difference(fecha) > Duration(days: plazoDias)) {
      throw VentaNoDevolvible('Pasaron más de $plazoDias días desde la venta: ya no admite cambios ni devoluciones.');
    }
    return venta;
  }

  /// Líneas de la venta agrupadas por variante (cantidad total y precio de la primera línea).
  Future<Map<String, Map<String, Object?>>> _itemsDeLaVenta(DatabaseExecutor ex, String ventaUuid) async {
    final filas = await ex.query(Schema.tablaOperacionesItems, where: 'operacion_uuid = ?', whereArgs: [ventaUuid], orderBy: 'id');
    final r = <String, Map<String, Object?>>{};
    for (final f in filas) {
      final k = _clave(f['producto_id'], f['talla_id'], f['color_id']);
      final previa = r[k];
      r[k] = previa == null ? {...f} : {...previa, 'cantidad': (previa['cantidad'] as int) + (f['cantidad'] as int)};
    }
    return r;
  }

  /// Unidades ya devueltas de esa venta por variante (las devoluciones rechazadas no cuentan).
  Future<Map<String, int>> _cantidadesYaDevueltas(DatabaseExecutor ex, String ventaUuid) async {
    final filas = await ex.rawQuery(
      'SELECT di.producto_id, di.talla_id, di.color_id, SUM(di.cantidad) AS n '
      'FROM ${Schema.tablaDevolucionesItems} di JOIN ${Schema.tablaDevoluciones} d ON d.id = di.devolucion_id '
      "WHERE d.venta_uuid = ? AND d.estado != 'rechazada' AND di.tipo_item = 'DEVUELTO' "
      'GROUP BY di.producto_id, di.talla_id, di.color_id',
      [ventaUuid],
    );
    return {for (final f in filas) _clave(f['producto_id'], f['talla_id'], f['color_id']): f['n'] as int};
  }

  // ---------------------------------------------------------------------------
  // Consultas para la pantalla
  // ---------------------------------------------------------------------------

  /// Ventas de contado de la sucursal (no rechazadas), de la más reciente a la más antigua.
  /// Con [texto] filtra por el comienzo del UUID / número de recibo (sin distinguir mayúsculas).
  Future<List<Map<String, dynamic>>> buscarVentas(int sucursalId, {String? texto, int limite = 30}) async {
    final db = await _db();
    try {
      final t = (texto ?? '').trim().toLowerCase();
      return await db.query(
        Schema.tablaOperaciones,
        columns: ['uuid', 'fecha', 'total_centavos', 'estado'],
        where: "tipo_operacion = 'VENTA_CONTADO' AND estado != 'rechazada' AND sucursal_id = ?"
            "${t.isEmpty ? '' : ' AND LOWER(uuid) LIKE ?'}",
        whereArgs: [sucursalId, if (t.isNotEmpty) '$t%'],
        orderBy: 'fecha DESC, rowid DESC',
        limit: limite,
      );
    } catch (e, st) {
      debugPrint('[DevolucionDao] Error al buscar ventas: $e\n$st');
      rethrow;
    }
  }

  /// La venta con sus líneas (por variante) y cuántas unidades de cada una ya se devolvieron; null si no existe.
  Future<Map<String, dynamic>?> obtenerVentaConItems(String ventaUuid) async {
    final db = await _db();
    try {
      final filas = await db.query(Schema.tablaOperaciones, where: 'uuid = ?', whereArgs: [ventaUuid]);
      if (filas.isEmpty) return null;
      final lineas = await _itemsDeLaVenta(db, ventaUuid);
      final devueltas = await _cantidadesYaDevueltas(db, ventaUuid);
      return {
        ...filas.first,
        'items': [
          for (final e in lineas.entries) {...e.value, 'cantidad_devuelta': devueltas[e.key] ?? 0},
        ],
      };
    } catch (e, st) {
      debugPrint('[DevolucionDao] Error al leer la venta $ventaUuid: $e\n$st');
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Sincronización
  // ---------------------------------------------------------------------------

  /// La devolución con el estado de su venta original (`estado_venta`) y sus ítems, o null.
  Future<Map<String, dynamic>?> obtenerParaSincronizar(String devolucionId) async {
    final db = await _db();
    final filas = await db.rawQuery(
      'SELECT d.*, o.estado AS estado_venta FROM ${Schema.tablaDevoluciones} d '
      'JOIN ${Schema.tablaOperaciones} o ON o.uuid = d.venta_uuid WHERE d.id = ?',
      [devolucionId],
    );
    return filas.isEmpty ? null : {...filas.first};
  }

  /// El servidor aceptó la devolución: cola 'sincronizado' y devolución 'sincronizada' con su id.
  Future<void> marcarSincronizada(String devolucionId, {required int idServidor}) async {
    final db = await _db();
    try {
      await db.transaction((Transaction txn) async {
        await _cerrarCola(txn, devolucionId, 'sincronizado', null);
        await txn.rawUpdate(
          'UPDATE ${Schema.tablaDevoluciones} SET estado = ?, id_servidor = ? WHERE id = ?',
          ['sincronizada', idServidor, devolucionId],
        );
      });
    } catch (e, st) {
      debugPrint('[DevolucionDao] Error al marcar sincronizada $devolucionId: $e\n$st');
      rethrow;
    }
  }

  /// El servidor rechazó la devolución (o su venta original fue rechazada): cola 'rechazado', devolución
  /// 'rechazada' y se DESHACE su efecto en el stock local, todo en una transacción. Deja de contar en el arqueo.
  Future<void> marcarRechazada(String devolucionId, String motivo) async {
    final db = await _db();
    try {
      await db.transaction((Transaction txn) async {
        final cola = await txn.query(Schema.tablaSyncQueue, columns: ['fecha_creacion'], where: 'devolucion_id = ?', whereArgs: [devolucionId]);
        if (cola.isEmpty) throw StateError('La devolución $devolucionId no está en la cola.');
        final fechaOperacion = cola.first['fecha_creacion'] as String;
        await _cerrarCola(txn, devolucionId, 'rechazado', motivo);

        final cab = await txn.query(Schema.tablaDevoluciones, columns: ['sucursal_id'], where: 'id = ?', whereArgs: [devolucionId]);
        final sucursalId = cab.first['sucursal_id'] as int;
        final items = await txn.query(Schema.tablaDevolucionesItems, where: 'devolucion_id = ?', whereArgs: [devolucionId]);
        for (final i in items) {
          // Lo devuelto sale otra vez de la estantería; lo nuevo vuelve a ella. Solo si el catálogo no se refrescó
          // desde el servidor después del registro (si se refrescó, esa cantidad ya es la real).
          final signo = i['tipo_item'] == Schema.itemDevuelto ? '-' : '+';
          final formula = signo == '-' ? 'MAX(cantidad_disponible - ?, 0)' : 'cantidad_disponible + ?';
          await txn.rawUpdate(
            'UPDATE ${Schema.tablaCatalogoLocal} SET cantidad_disponible = $formula '
            'WHERE sucursal_id = ? AND producto_id = ? AND IFNULL(talla_id, 0) = IFNULL(?, 0) '
            'AND IFNULL(color_id, 0) = IFNULL(?, 0) AND sincronizado_en <= ?',
            [i['cantidad'], sucursalId, i['producto_id'], i['talla_id'], i['color_id'], fechaOperacion],
          );
        }
        await txn.rawUpdate('UPDATE ${Schema.tablaDevoluciones} SET estado = ? WHERE id = ?', ['rechazada', devolucionId]);
        await PuntosDao.cancelarPorOperacionEn(txn, devolucionId); // los puntos que se habían restado se devuelven
      });
    } catch (e, st) {
      debugPrint('[DevolucionDao] Error al marcar rechazada $devolucionId: $e\n$st');
      rethrow;
    }
  }

  Future<void> _cerrarCola(Transaction txn, String devolucionId, String estado, String? motivo) async {
    final filas = await txn.rawUpdate(
      'UPDATE ${Schema.tablaSyncQueue} SET estado = ?, ultimo_error = ?, fecha_ultimo_intento = ? '
      "WHERE devolucion_id = ? AND estado IN ('pendiente', 'en_proceso')",
      [estado, motivo, DateTime.now().toUtc().toIso8601String(), devolucionId],
    );
    if (filas != 1) throw StateError('La devolución $devolucionId no está pendiente de sincronizar.');
  }
}

class _Linea {
  const _Linea(this.productoId, this.tallaId, this.colorId, this.cantidad);

  final int productoId;
  final int? tallaId;
  final int? colorId;
  final int cantidad;
}
