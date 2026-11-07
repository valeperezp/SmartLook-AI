/** CU11 — cambios y devoluciones: lo que devuelve el backend (que es quien valida el plazo, las cantidades y el stock). */

export interface ItemVentaDevolvible {
  producto_id: number;
  nombre_producto: string;
  talla_id: number | null;
  nombre_talla: string | null;
  color_id: number | null;
  nombre_color: string | null;
  cantidad_vendida: number;
  cantidad_devuelta: number;
  /** Cuántas se pueden todavía devolver (vendidas menos ya devueltas). */
  cantidad_devolvible: number;
  precio_unitario: number;
}

export interface VentaDevolvible {
  venta_id: number;
  /** Id con el que la app móvil mandó la venta (si vino de una app). */
  uuid: string | null;
  /** Lo que ve el cliente en su ticket: el uuid abreviado o #id. */
  recibo: string;
  sucursal_id: number;
  nombre_sucursal: string | null;
  estado: string;
  total: number;
  creada_en: string;
  plazo_dias: number;
  dias_transcurridos: number;
  /** Informativo: la decisión la toma el servidor al registrar. */
  dentro_de_plazo: boolean;
  items: ItemVentaDevolvible[];
}

export type TipoDevolucion = 'devolucion' | 'cambio';

export interface ItemDevolucionIn {
  producto_id: number;
  talla_id: number | null;
  color_id: number | null;
  cantidad: number;
}

export interface DevolucionCreate {
  venta_id: number;
  tipo: TipoDevolucion;
  motivo?: string;
  items_devueltos: ItemDevolucionIn[];
  items_nuevos: ItemDevolucionIn[];
  uuid?: string;
}

export interface ItemDevolucionOut {
  tipo_item: 'devuelto' | 'nuevo';
  producto_id: number;
  nombre_producto: string;
  nombre_talla: string | null;
  nombre_color: string | null;
  cantidad: number;
  precio_unitario: number;
}

export interface DevolucionOut {
  id: number;
  uuid: string;
  venta_id: number;
  tipo: string;
  motivo: string | null;
  /** Lo que se reembolsa (al precio de la venta original). */
  total_devuelto: number;
  /** Lo que cuesta lo que se lleva (al precio vigente). */
  total_nuevo: number;
  /** nuevo - devuelto: > 0 el cliente paga la diferencia · < 0 se le devuelve. */
  diferencia: number;
  items: ItemDevolucionOut[];
}
