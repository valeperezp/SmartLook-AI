// Esquema v1 congelado: sirve para probar la migración a v2 con datos reales.
const List<String> ddlV1 = [
  '''
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
)''',
  '''
CREATE UNIQUE INDEX ux_catalogo_variante ON catalogo_local
  (sucursal_id, producto_id, IFNULL(talla_id, 0), IFNULL(color_id, 0))''',
  '''
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
  CHECK (tipo_operacion <> 'VENTA_CONTADO' OR cajero_id IS NOT NULL),
  CHECK (tipo_operacion <> 'RESERVA_CLIENTE' OR cliente_id IS NOT NULL),
  CHECK (estado <> 'sincronizada' OR id_servidor IS NOT NULL)
)''',
  '''
CREATE TABLE operaciones_locales_items (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  operacion_uuid TEXT NOT NULL REFERENCES operaciones_locales(uuid) ON DELETE CASCADE,
  producto_id INTEGER NOT NULL,
  talla_id INTEGER,
  color_id INTEGER,
  nombre_producto TEXT NOT NULL,
  cantidad INTEGER NOT NULL CHECK (cantidad > 0),
  precio_unitario_centavos INTEGER NOT NULL CHECK (precio_unitario_centavos >= 0)
)''',
  '''
CREATE INDEX ix_items_operacion ON operaciones_locales_items (operacion_uuid)''',
  '''
CREATE TABLE sync_queue (
  id TEXT PRIMARY KEY,
  tipo_operacion TEXT NOT NULL CHECK (tipo_operacion IN ('VENTA_CONTADO', 'RESERVA_CLIENTE')),
  operacion_uuid TEXT REFERENCES operaciones_locales(uuid) ON DELETE RESTRICT,
  payload_json TEXT NOT NULL,
  estado TEXT NOT NULL DEFAULT 'pendiente'
    CHECK (estado IN ('pendiente', 'en_proceso', 'sincronizado', 'error', 'rechazado')),
  intentos INTEGER NOT NULL DEFAULT 0 CHECK (intentos >= 0),
  ultimo_error TEXT,
  fecha_ultimo_intento TEXT,
  fecha_creacion TEXT NOT NULL
)''',
  '''
CREATE INDEX ix_sync_cola ON sync_queue (estado, fecha_creacion)''',
];
