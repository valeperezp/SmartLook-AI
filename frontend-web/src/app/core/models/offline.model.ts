/** Modelos de la base local (IndexedDB) de la web offline. Misma forma que el móvil (`catalogo_local`, `operaciones_locales`, `sync_queue`). */

/** Una variante (producto + talla + color) de una sucursal con su stock, guardada para consultarla sin conexión. */
export interface ItemCatalogoLocal {
  /** Clave: `${empresa}|${sucursal_id}|${producto_id}|${talla_id ?? 0}|${color_id ?? 0}`. */
  clave: string;
  /** Tienda a la que pertenece (slug o id): el navegador es compartido y no se deben mezclar catálogos. */
  empresa: string;
  sucursal_id: number;
  nombre_sucursal: string;
  producto_id: number;
  nombre_producto: string;
  descripcion: string | null;
  categoria_id: number | null;
  nombre_categoria: string | null;
  talla_id: number | null;
  nombre_talla: string | null;
  color_id: number | null;
  nombre_color: string | null;
  precio_centavos: number;
  imagen_url: string | null;
  cantidad_disponible: number;
  sincronizado_en: string;
}

export type TipoOperacionLocal = 'VENTA_CONTADO' | 'RESERVA_CLIENTE';

/** pendiente → (sincronizada | rechazada). Una operación pendiente nunca se pierde: se reintenta. */
export type EstadoOperacionLocal = 'pendiente' | 'sincronizada' | 'rechazada';

export interface ItemOperacionLocal {
  producto_id: number;
  talla_id: number | null;
  color_id: number | null;
  nombre_producto?: string;
  cantidad: number;
  precio_unitario_centavos: number;
}

/** Lo que hace falta para registrar una operación sin conexión; el uuid, el estado y las fechas los pone el servicio. */
export interface NuevaOperacionLocal {
  tipo_operacion: TipoOperacionLocal;
  sucursal_id: number;
  cajero_id?: number | null;
  cliente_id?: number | null;
  items: ItemOperacionLocal[];
}

export interface OperacionLocal {
  /** id local = clave de idempotencia: el backend no duplica una operación con el mismo uuid. */
  uuid: string;
  tipo_operacion: TipoOperacionLocal;
  sucursal_id: number;
  cajero_id: number | null;
  cliente_id: number | null;
  /** Usuario que la registró: solo se envía con la sesión de ese mismo usuario. */
  usuario_id: number | null;
  fecha: string;
  total_centavos: number;
  items: ItemOperacionLocal[];
  estado: EstadoOperacionLocal;
  id_servidor: number | null;
  /** Motivo del rechazo o de la espera, tal como lo dijo el servidor. */
  mensaje: string | null;
  /**
   * Esta operación restó stock de `catalogo_local` al guardarse. Si el servidor la rechaza (CU13) ese stock se devuelve
   * y la marca pasa a false para no devolverlo dos veces. Ausente en operaciones guardadas antes de existir esta marca.
   */
  stock_local_descontado?: boolean;
}

export type EstadoCola = 'pendiente' | 'en_proceso' | 'sincronizado' | 'rechazado';

/** Entrada de la cola de envío de una operación: lleva los intentos y el último error. */
export interface EntradaCola {
  /** Mismo valor que el uuid de la operación (una entrada por operación). */
  id: string;
  tipo_operacion: TipoOperacionLocal;
  estado: EstadoCola;
  intentos: number;
  ultimo_error: string | null;
  fecha_creacion: string;
  fecha_ultimo_intento: string | null;
}

/** Cuerpo de `POST /sync/operaciones`: el mismo JSON que envía la app móvil. */
export interface OperacionSyncPayload {
  uuid: string;
  tipo_operacion: TipoOperacionLocal;
  sucursal_id: number;
  cajero_id: number | null;
  cliente_id: number | null;
  fecha: string;
  total_centavos: number;
  items: {
    producto_id: number;
    talla_id: number | null;
    color_id: number | null;
    cantidad: number;
    precio_unitario_centavos: number;
  }[];
}

export interface ResultadoSyncItem {
  uuid: string;
  status: 'ok' | 'conflict' | 'pendiente';
  id_servidor?: number | null;
  entidad?: string | null;
  message?: string | null;
}

export interface ResultadoSyncWeb {
  sincronizadas: number;
  rechazadas: number;
  /** Quedaron pendientes por un error de red o del servidor: se reintentan. */
  fallidas: number;
  /** El servidor respondió "pendiente" (falta algo por sincronizar). */
  enEspera: number;
  sinRed: boolean;
  sesionExpirada: boolean;
  yaEnCurso: boolean;
}
