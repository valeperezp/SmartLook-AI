/** CU16 — "Avísame cuando llegue": suscripciones de stock y avisos del servidor. */

export interface Suscripcion {
  id: number;
  /** Id local con el que se mandó (si se guardó sin conexión): reenviarlo no duplica. */
  uuid: string | null;
  producto_id: number;
  nombre_producto: string;
  talla_id: number | null;
  nombre_talla: string | null;
  color_id: number | null;
  nombre_color: string | null;
  sucursal_id: number | null;
  nombre_sucursal: string | null;
  /** "Camiseta · Talla M · Blanco". */
  descripcion: string;
  /** pendiente = espera stock · notificado = ya llegó. */
  estado: 'pendiente' | 'notificado';
  fecha: string | null;
  notificado_en: string | null;
  /** El cliente ya vio el aviso. */
  visto: boolean;
}

export interface SuscripcionCreate {
  producto_id: number;
  talla_id?: number | null;
  color_id?: number | null;
  sucursal_id?: number | null;
  uuid?: string;
}

/** Una suscripción hecha sin conexión, guardada en IndexedDB hasta poder enviarla. */
export interface SuscripcionPendienteLocal {
  uuid: string;
  cliente_id: number;
  producto_id: number;
  nombre_producto: string;
  talla_id: number | null;
  color_id: number | null;
  sucursal_id: number | null;
  creada_en: string;
}
