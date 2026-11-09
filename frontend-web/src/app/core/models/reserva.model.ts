export interface ReservaItem {
  id: number;
  producto_id: number;
  talla_id: number | null;
  color_id: number | null;
  cantidad: number;
  nombre_producto: string;
  nombre_talla: string | null;
  nombre_color: string | null;
  precio_unitario: number;
}

/** Devolución de DINERO de un pedido cancelado. El cliente adjunta su QR bancario; el personal le transfiere y lo marca. */
export interface Reembolso {
  id: number;
  estado: 'pendiente' | 'reembolsado';
  reserva_id: number | null;
  venta_id: number | null;
  cliente_id: number | null;
  monto: number;
  tiene_qr: boolean;
  /** Imagen del QR bancario que subió el cliente (null si todavía no lo hizo). */
  qr_devolucion_url: string | null;
  qr_subido_en?: string | null;
  procesado_en?: string | null;
}

/** Lo que ve el personal de un reembolso pendiente: además, de quién y de qué pedido es (una compra o una reserva). */
export interface ReembolsoDetalle extends Reembolso {
  origen: 'reserva' | 'venta';
  sucursal_id: number;
  nombre_sucursal?: string | null;
  nombre_cliente?: string | null;
  email_cliente?: string | null;
}

export interface Reserva {
  id: number;
  cliente_id: number;
  sucursal_id: number;
  estado: 'pendiente' | 'confirmada' | 'atendida' | 'cancelada' | 'reembolsada';
  horario_aproximado: string | null;
  creada_en: string;
  nombre_sucursal?: string;
  nombre_cliente?: string | null;
  email_cliente?: string | null;
  items: ReservaItem[];
  total_items: number;
  total_unidades: number;
  total_estimado: number;
  /** Si el pedido está cancelado: su reembolso (con el QR del cliente, si lo subió). */
  reembolso?: Reembolso | null;
}

export interface ReservaItemCreate {
  producto_id: number;
  talla_id?: number | null;
  color_id?: number | null;
  cantidad: number;
}

export interface ReservaCreate {
  sucursal_id: number;
  horario_aproximado?: string | null;
  items: ReservaItemCreate[];
}
