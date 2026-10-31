/// Esquema SQLite del módulo offline.
///
/// - Dinero en centavos enteros (INTEGER); fechas en ISO-8601 UTC (TEXT).
/// - `catalogo_local` es una caché de solo lectura: la fuente de verdad es el servidor.
/// - `operaciones_locales` cubre las dos operaciones que se pueden hacer sin red:
///   VENTA_CONTADO (cajero) y RESERVA_CLIENTE (cliente).
/// - `turnos_caja` es el turno del cajero (apertura con monto inicial, arqueo al cierre). Solo las ventas
///   del cajero se vinculan a un turno (`operaciones_locales.turno_uuid`); las reservas no.
/// - `sync_queue` también transporta el CIERRE_CAJA de un turno y las DEVOLUCION (cambios/devoluciones), que
///   no tienen fila en `operaciones_locales`.
/// - `devoluciones_locales` (+ ítems) registra los cambios y devoluciones de una venta; su efecto neto en
///   efectivo (nuevo - devuelto) entra al arqueo del turno.
/// - Los ítems guardan una copia del nombre/precio al momento de la operación, sin FK
///   a `catalogo_local` (esa tabla se reemplaza completa en cada sincronización).
class Schema {
  Schema._();

  static const int version = 4;
  static const String nombreArchivo = 'smartlook_offline.db';

  static const String tablaCatalogoLocal = 'catalogo_local';
  static const String tablaOperaciones = 'operaciones_locales';
  static const String tablaOperacionesItems = 'operaciones_locales_items';
  static const String tablaSyncQueue = 'sync_queue';
  static const String tablaTurnosCaja = 'turnos_caja';
  static const String tablaDevoluciones = 'devoluciones_locales';
  static const String tablaDevolucionesItems = 'devoluciones_locales_items';
  static const String tablaPuntosCliente = 'puntos_cliente';
  static const String tablaMovimientosPuntos = 'movimientos_puntos';
  static const String tablaSuscripcionesStock = 'suscripciones_stock';

  static const String tipoVentaContado = 'VENTA_CONTADO';
  static const String tipoReservaCliente = 'RESERVA_CLIENTE';
  static const String tipoCierreCaja = 'CIERRE_CAJA';

  /// Tipo de la entrada de `sync_queue` para un cambio o devolución.
  static const String tipoOperacionDevolucion = 'DEVOLUCION';

  /// Tipos de `sync_queue` para los movimientos de puntos de fidelización.
  static const String tipoPuntosOtorgados = 'PUNTOS_OTORGADOS';
  static const String tipoPuntosRestados = 'PUNTOS_RESTADOS';

  static const String puntosGanado = 'ganado';
  static const String puntosPerdido = 'perdido';
  static const String puntosCanjeado = 'canjeado';

  static const String suscripcionPendiente = 'pendiente';
  static const String suscripcionNotificado = 'notificado';
  static const String suscripcionExpirado = 'expirado';

  /// Clase de movimiento dentro de `devoluciones_locales.tipo`.
  static const String devolucionCambio = 'CAMBIO';
  static const String devolucionSoloDevolucion = 'DEVOLUCION';
  static const String itemDevuelto = 'DEVUELTO';
  static const String itemNuevo = 'NUEVO';

  /// Tipos de operación del usuario (las que tienen fila en `operaciones_locales`).
  static const List<String> tiposOperacion = [tipoVentaContado, tipoReservaCliente];

  static const String turnoAbierto = 'abierto';
  static const String turnoCerrado = 'cerrado';
  static const String turnoSincronizado = 'sincronizado';

  static const String estadoPendiente = 'pendiente';

  static const String _catalogoLocal = '''
CREATE TABLE catalogo_local (
  inventario_id INTEGER PRIMARY KEY,
  sucursal_id INTEGER NOT NULL,
  producto_id INTEGER NOT NULL,
  talla_id INTEGER,
  color_id INTEGER,
  nombre_producto TEXT NOT NULL,
  nombre_talla TEXT,
  nombre_color TEXT,
  precio_centavos INTEGER NOT NULL CHECK (precio_centavos >= 0),
  imagen_url TEXT,
  cantidad_disponible INTEGER NOT NULL CHECK (cantidad_disponible >= 0),
  activo INTEGER NOT NULL DEFAULT 1 CHECK (activo IN (0, 1)),
  sincronizado_en TEXT NOT NULL
)''';

  static const String _indiceCatalogoVariante = '''
CREATE UNIQUE INDEX ux_catalogo_variante ON catalogo_local
  (sucursal_id, producto_id, IFNULL(talla_id, 0), IFNULL(color_id, 0))''';

  static const String _operacionesLocales = '''
CREATE TABLE operaciones_locales (
  uuid TEXT PRIMARY KEY,
  tipo_operacion TEXT NOT NULL CHECK (tipo_operacion IN ('VENTA_CONTADO', 'RESERVA_CLIENTE')),
  sucursal_id INTEGER NOT NULL,
  cajero_id INTEGER,
  cliente_id INTEGER,
  total_centavos INTEGER NOT NULL CHECK (total_centavos >= 0),
  fecha TEXT NOT NULL,
  estado TEXT NOT NULL DEFAULT 'pendiente_sync'
    CHECK (estado IN ('pendiente_sync', 'sincronizada', 'rechazada')),
  id_servidor INTEGER,
  turno_uuid TEXT REFERENCES turnos_caja(id),
  CHECK (tipo_operacion <> 'VENTA_CONTADO' OR cajero_id IS NOT NULL),
  CHECK (tipo_operacion <> 'RESERVA_CLIENTE' OR cliente_id IS NOT NULL),
  CHECK (estado <> 'sincronizada' OR id_servidor IS NOT NULL)
)''';

  static const String _operacionesLocalesItems = '''
CREATE TABLE operaciones_locales_items (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  operacion_uuid TEXT NOT NULL REFERENCES operaciones_locales(uuid) ON DELETE CASCADE,
  producto_id INTEGER NOT NULL,
  talla_id INTEGER,
  color_id INTEGER,
  nombre_producto TEXT NOT NULL,
  cantidad INTEGER NOT NULL CHECK (cantidad > 0),
  precio_unitario_centavos INTEGER NOT NULL CHECK (precio_unitario_centavos >= 0)
)''';

  static const String _turnosCaja = '''
CREATE TABLE turnos_caja (
  id TEXT PRIMARY KEY,
  cajero_id INTEGER NOT NULL,
  sucursal_id INTEGER NOT NULL,
  monto_inicial_centavos INTEGER NOT NULL CHECK (monto_inicial_centavos >= 0),
  fecha_apertura TEXT NOT NULL,
  monto_esperado_centavos INTEGER,
  monto_real_centavos INTEGER CHECK (monto_real_centavos IS NULL OR monto_real_centavos >= 0),
  diferencia_centavos INTEGER,
  estado TEXT NOT NULL DEFAULT 'abierto' CHECK (estado IN ('abierto', 'cerrado', 'sincronizado')),
  fecha_cierre TEXT,
  id_servidor INTEGER,
  CHECK (estado = 'abierto' OR (monto_esperado_centavos IS NOT NULL AND monto_real_centavos IS NOT NULL
         AND diferencia_centavos IS NOT NULL AND fecha_cierre IS NOT NULL)),
  CHECK (estado <> 'sincronizado' OR id_servidor IS NOT NULL)
)''';

  /// Un cajero no puede tener dos turnos abiertos a la vez en la misma sucursal.
  static const String _indiceTurnoAbierto =
      "CREATE UNIQUE INDEX ux_turno_abierto ON turnos_caja (cajero_id, sucursal_id) WHERE estado = 'abierto'";

  static const String _indiceOperacionesTurno = '''
CREATE INDEX ix_operaciones_turno ON operaciones_locales (turno_uuid)''';

  /// `sync_queue` tal como era en v2 (la migración v1 → v2 la crea así; v3 la vuelve a reconstruir).
  static const String _syncQueueV2 = '''
CREATE TABLE sync_queue (
  id TEXT PRIMARY KEY,
  tipo_operacion TEXT NOT NULL
    CHECK (tipo_operacion IN ('VENTA_CONTADO', 'RESERVA_CLIENTE', 'CIERRE_CAJA')),
  operacion_uuid TEXT REFERENCES operaciones_locales(uuid) ON DELETE RESTRICT,
  turno_uuid TEXT REFERENCES turnos_caja(id) ON DELETE RESTRICT,
  payload_json TEXT NOT NULL,
  estado TEXT NOT NULL DEFAULT 'pendiente'
    CHECK (estado IN ('pendiente', 'en_proceso', 'sincronizado', 'error', 'rechazado')),
  intentos INTEGER NOT NULL DEFAULT 0 CHECK (intentos >= 0),
  ultimo_error TEXT,
  fecha_ultimo_intento TEXT,
  fecha_creacion TEXT NOT NULL,
  CHECK (tipo_operacion <> 'CIERRE_CAJA' OR (turno_uuid IS NOT NULL AND operacion_uuid IS NULL))
)''';

  static const String _devolucionesLocales = '''
CREATE TABLE devoluciones_locales (
  id TEXT PRIMARY KEY,
  venta_uuid TEXT NOT NULL REFERENCES operaciones_locales(uuid),
  tipo TEXT NOT NULL CHECK (tipo IN ('CAMBIO', 'DEVOLUCION')),
  motivo TEXT,
  cajero_id INTEGER NOT NULL,
  sucursal_id INTEGER NOT NULL,
  total_devuelto_centavos INTEGER NOT NULL CHECK (total_devuelto_centavos >= 0),
  total_nuevo_centavos INTEGER NOT NULL DEFAULT 0 CHECK (total_nuevo_centavos >= 0),
  fecha TEXT NOT NULL,
  turno_uuid TEXT NOT NULL REFERENCES turnos_caja(id),
  estado TEXT NOT NULL DEFAULT 'pendiente_sync'
    CHECK (estado IN ('pendiente_sync', 'sincronizada', 'rechazada')),
  id_servidor INTEGER,
  CHECK (tipo <> 'DEVOLUCION' OR total_nuevo_centavos = 0),
  CHECK (estado <> 'sincronizada' OR id_servidor IS NOT NULL)
)''';

  static const String _devolucionesLocalesItems = '''
CREATE TABLE devoluciones_locales_items (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  devolucion_id TEXT NOT NULL REFERENCES devoluciones_locales(id) ON DELETE CASCADE,
  producto_id INTEGER NOT NULL,
  talla_id INTEGER,
  color_id INTEGER,
  nombre_producto TEXT NOT NULL,
  cantidad INTEGER NOT NULL CHECK (cantidad > 0),
  precio_centavos INTEGER NOT NULL CHECK (precio_centavos >= 0),
  tipo_item TEXT NOT NULL CHECK (tipo_item IN ('DEVUELTO', 'NUEVO'))
)''';

  static const String _indiceDevolucionesVenta = '''
CREATE INDEX ix_devoluciones_venta ON devoluciones_locales (venta_uuid)''';

  static const String _indiceDevolucionesTurno = '''
CREATE INDEX ix_devoluciones_turno ON devoluciones_locales (turno_uuid)''';

  static const String _indiceDevolucionesItems = '''
CREATE INDEX ix_devoluciones_items ON devoluciones_locales_items (devolucion_id)''';

  static const String _syncQueueV3 = '''
CREATE TABLE sync_queue (
  id TEXT PRIMARY KEY,
  tipo_operacion TEXT NOT NULL
    CHECK (tipo_operacion IN ('VENTA_CONTADO', 'RESERVA_CLIENTE', 'CIERRE_CAJA', 'DEVOLUCION')),
  operacion_uuid TEXT REFERENCES operaciones_locales(uuid) ON DELETE RESTRICT,
  turno_uuid TEXT REFERENCES turnos_caja(id) ON DELETE RESTRICT,
  devolucion_id TEXT REFERENCES devoluciones_locales(id) ON DELETE RESTRICT,
  payload_json TEXT NOT NULL,
  estado TEXT NOT NULL DEFAULT 'pendiente'
    CHECK (estado IN ('pendiente', 'en_proceso', 'sincronizado', 'error', 'rechazado')),
  intentos INTEGER NOT NULL DEFAULT 0 CHECK (intentos >= 0),
  ultimo_error TEXT,
  fecha_ultimo_intento TEXT,
  fecha_creacion TEXT NOT NULL,
  CHECK (tipo_operacion <> 'CIERRE_CAJA' OR (turno_uuid IS NOT NULL AND operacion_uuid IS NULL)),
  CHECK (tipo_operacion <> 'DEVOLUCION' OR
         (devolucion_id IS NOT NULL AND operacion_uuid IS NULL AND turno_uuid IS NULL))
)''';
  // v4: la `sync_queue` vigente (se reconstruye otra vez al migrar de v3).
  static const String _syncQueue = '''
CREATE TABLE sync_queue (
  id TEXT PRIMARY KEY,
  tipo_operacion TEXT NOT NULL
    CHECK (tipo_operacion IN ('VENTA_CONTADO', 'RESERVA_CLIENTE', 'CIERRE_CAJA', 'DEVOLUCION',
                              'PUNTOS_OTORGADOS', 'PUNTOS_RESTADOS')),
  operacion_uuid TEXT REFERENCES operaciones_locales(uuid) ON DELETE RESTRICT,
  turno_uuid TEXT REFERENCES turnos_caja(id) ON DELETE RESTRICT,
  devolucion_id TEXT REFERENCES devoluciones_locales(id) ON DELETE RESTRICT,
  movimiento_puntos_id TEXT REFERENCES movimientos_puntos(id) ON DELETE RESTRICT,
  payload_json TEXT NOT NULL,
  estado TEXT NOT NULL DEFAULT 'pendiente'
    CHECK (estado IN ('pendiente', 'en_proceso', 'sincronizado', 'error', 'rechazado')),
  intentos INTEGER NOT NULL DEFAULT 0 CHECK (intentos >= 0),
  ultimo_error TEXT,
  fecha_ultimo_intento TEXT,
  fecha_creacion TEXT NOT NULL,
  CHECK (tipo_operacion <> 'CIERRE_CAJA' OR (turno_uuid IS NOT NULL AND operacion_uuid IS NULL)),
  CHECK (tipo_operacion <> 'DEVOLUCION' OR
         (devolucion_id IS NOT NULL AND operacion_uuid IS NULL AND turno_uuid IS NULL)),
  CHECK (tipo_operacion NOT IN ('PUNTOS_OTORGADOS', 'PUNTOS_RESTADOS') OR
         (movimiento_puntos_id IS NOT NULL AND operacion_uuid IS NULL AND turno_uuid IS NULL
          AND devolucion_id IS NULL))
)''';

  static const String _puntosCliente = '''
CREATE TABLE puntos_cliente (
  cliente_id INTEGER PRIMARY KEY,
  saldo INTEGER NOT NULL DEFAULT 0 CHECK (saldo >= 0),
  ultima_actualizacion TEXT
)''';

  /// `operacion_uuid` es la venta o devolución que generó el movimiento; `venta_uuid` es siempre la venta de
  /// origen (para repartir los puntos de una venta entre sus devoluciones).
  static const String _movimientosPuntos = '''
CREATE TABLE movimientos_puntos (
  id TEXT PRIMARY KEY,
  cliente_id INTEGER NOT NULL REFERENCES puntos_cliente(cliente_id),
  operacion_uuid TEXT NOT NULL,
  venta_uuid TEXT NOT NULL,
  tipo TEXT NOT NULL CHECK (tipo IN ('ganado', 'canjeado', 'perdido')),
  cantidad INTEGER NOT NULL CHECK (cantidad > 0),
  fecha TEXT NOT NULL,
  estado_sync TEXT NOT NULL DEFAULT 'pendiente'
    CHECK (estado_sync IN ('pendiente', 'sincronizado', 'rechazado'))
)''';

  static const String _indiceMovimientosPuntos = '''
CREATE INDEX ix_movimientos_puntos_cliente ON movimientos_puntos (cliente_id, fecha)''';

  static const String _indiceMovimientosVenta = '''
CREATE INDEX ix_movimientos_puntos_venta ON movimientos_puntos (venta_uuid)''';

  static const String _suscripcionesStock = '''
CREATE TABLE suscripciones_stock (
  id TEXT PRIMARY KEY,
  cliente_id INTEGER NOT NULL,
  producto_id INTEGER NOT NULL,
  talla_id INTEGER,
  color_id INTEGER,
  sucursal_id INTEGER,
  descripcion TEXT NOT NULL,
  fecha_suscripcion TEXT NOT NULL,
  estado TEXT NOT NULL DEFAULT 'pendiente' CHECK (estado IN ('pendiente', 'notificado', 'expirado')),
  fecha_notificacion TEXT,
  visto INTEGER NOT NULL DEFAULT 0 CHECK (visto IN (0, 1))
)''';

  /// Un cliente no puede tener dos avisos pendientes por la misma variante en la misma sucursal.
  static const String _indiceSuscripcionPendiente =
      "CREATE UNIQUE INDEX ux_suscripcion_pendiente ON suscripciones_stock "
      "(cliente_id, producto_id, IFNULL(talla_id, 0), IFNULL(color_id, 0), IFNULL(sucursal_id, 0)) "
      "WHERE estado = 'pendiente'";

  static const String _indiceSuscripcionesCliente = '''
CREATE INDEX ix_suscripciones_cliente ON suscripciones_stock (cliente_id, estado)''';

  static const String _indiceSyncCola = '''
CREATE INDEX ix_sync_cola ON sync_queue (estado, fecha_creacion)''';

  static const String _indiceItemsOperacion = '''
CREATE INDEX ix_items_operacion ON operaciones_locales_items (operacion_uuid)''';

  /// Sentencias a ejecutar en `onCreate`, en orden (las tablas referenciadas van primero).
  static const List<String> ddl = [
    _catalogoLocal,
    _indiceCatalogoVariante,
    _turnosCaja,
    _indiceTurnoAbierto,
    _operacionesLocales,
    _operacionesLocalesItems,
    _indiceItemsOperacion,
    _indiceOperacionesTurno,
    _devolucionesLocales,
    _devolucionesLocalesItems,
    _indiceDevolucionesVenta,
    _indiceDevolucionesTurno,
    _indiceDevolucionesItems,
    _puntosCliente,
    _movimientosPuntos,
    _indiceMovimientosPuntos,
    _indiceMovimientosVenta,
    _suscripcionesStock,
    _indiceSuscripcionPendiente,
    _indiceSuscripcionesCliente,
    _syncQueue,
    _indiceSyncCola,
  ];

  /// v1 → v2: turnos de caja. Conserva todos los datos existentes.
  /// SQLite no puede cambiar un CHECK con ALTER, así que `sync_queue` (cuyo CHECK ahora admite CIERRE_CAJA y
  /// que gana `turno_uuid`) se reconstruye copiando sus filas; nadie la referencia, así que es seguro.
  static List<String> get migracionV2 => [
        _turnosCaja,
        _indiceTurnoAbierto,
        'ALTER TABLE operaciones_locales ADD COLUMN turno_uuid TEXT REFERENCES turnos_caja(id)',
        _indiceOperacionesTurno,
        _syncQueueV2.replaceFirst('CREATE TABLE sync_queue', 'CREATE TABLE sync_queue_nueva'),
        'INSERT INTO sync_queue_nueva (id, tipo_operacion, operacion_uuid, payload_json, estado, intentos, '
            'ultimo_error, fecha_ultimo_intento, fecha_creacion) '
            'SELECT id, tipo_operacion, operacion_uuid, payload_json, estado, intentos, '
            'ultimo_error, fecha_ultimo_intento, fecha_creacion FROM sync_queue',
        'DROP TABLE sync_queue',
        'ALTER TABLE sync_queue_nueva RENAME TO sync_queue',
        _indiceSyncCola,
      ];

  /// v2 → v3: cambios y devoluciones. `sync_queue` se reconstruye otra vez (su CHECK admite DEVOLUCION y gana
  /// `devolucion_id`) copiando todas sus filas.
  static List<String> get migracionV3 => [
        _devolucionesLocales,
        _devolucionesLocalesItems,
        _indiceDevolucionesVenta,
        _indiceDevolucionesTurno,
        _indiceDevolucionesItems,
        _syncQueueV3.replaceFirst('CREATE TABLE sync_queue', 'CREATE TABLE sync_queue_nueva'),
        'INSERT INTO sync_queue_nueva (id, tipo_operacion, operacion_uuid, turno_uuid, payload_json, estado, '
            'intentos, ultimo_error, fecha_ultimo_intento, fecha_creacion) '
            'SELECT id, tipo_operacion, operacion_uuid, turno_uuid, payload_json, estado, '
            'intentos, ultimo_error, fecha_ultimo_intento, fecha_creacion FROM sync_queue',
        'DROP TABLE sync_queue',
        'ALTER TABLE sync_queue_nueva RENAME TO sync_queue',
        _indiceSyncCola,
      ];

  /// v3 → v4: puntos de fidelización y avisos de stock. `sync_queue` se reconstruye otra vez (admite
  /// PUNTOS_OTORGADOS / PUNTOS_RESTADOS y gana `movimiento_puntos_id`) copiando todas sus filas.
  static List<String> get migracionV4 => [
        _puntosCliente,
        _movimientosPuntos,
        _indiceMovimientosPuntos,
        _indiceMovimientosVenta,
        _suscripcionesStock,
        _indiceSuscripcionPendiente,
        _indiceSuscripcionesCliente,
        _syncQueue.replaceFirst('CREATE TABLE sync_queue', 'CREATE TABLE sync_queue_nueva'),
        'INSERT INTO sync_queue_nueva (id, tipo_operacion, operacion_uuid, turno_uuid, devolucion_id, payload_json, '
            'estado, intentos, ultimo_error, fecha_ultimo_intento, fecha_creacion) '
            'SELECT id, tipo_operacion, operacion_uuid, turno_uuid, devolucion_id, payload_json, '
            'estado, intentos, ultimo_error, fecha_ultimo_intento, fecha_creacion FROM sync_queue',
        'DROP TABLE sync_queue',
        'ALTER TABLE sync_queue_nueva RENAME TO sync_queue',
        _indiceSyncCola,
      ];
}
