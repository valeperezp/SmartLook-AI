/** CU13 — ventas hechas offline que el servidor no pudo cumplir por falta de stock y esperan que un encargado las resuelva. */

export interface ConflictoItem {
  producto_id: number;
  nombre_producto: string;
  talla_id: number | null;
  nombre_talla: string | null;
  color_id: number | null;
  nombre_color: string | null;
  cantidad: number;
  precio_unitario: number;
}

export interface ConflictoSync {
  venta_id: number;
  /** Id con el que el dispositivo mandó la venta. */
  uuid: string | null;
  sucursal_id: number;
  nombre_sucursal: string | null;
  cajero_id: number | null;
  nombre_cajero: string | null;
  total: number;
  creada_en: string | null;
  /** Qué falló, p. ej. "Stock insuficiente en Camisa Talla M. Disponible: 1, solicitado: 3". */
  motivo: string | null;
  items: ConflictoItem[];
}

export type AccionConflicto = 'ANULAR' | 'AJUSTAR' | 'FORZAR';

/** Una prenda del ajuste (AJUSTAR): la variante nueva que se entrega en lugar de la original. */
export interface ItemAjuste {
  producto_id: number;
  talla_id: number | null;
  color_id: number | null;
  cantidad: number;
}

export interface ResolverConflictoRequest {
  accion: AccionConflicto;
  items?: ItemAjuste[];
  motivo?: string;
}

export interface ResolverConflictoResponse {
  venta_id: number;
  accion: AccionConflicto;
  /** completada (FORZAR / AJUSTAR) o anulada (ANULAR). */
  estado: string;
  total: number;
}
