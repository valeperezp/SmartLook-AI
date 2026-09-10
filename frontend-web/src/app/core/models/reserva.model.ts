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

export interface Reserva {
  id: number;
  cliente_id: number;
  sucursal_id: number;
  estado: 'pendiente' | 'confirmada' | 'atendida' | 'cancelada';
  horario_aproximado: string | null;
  creada_en: string;
  nombre_sucursal?: string;
  items: ReservaItem[];
  total_items: number;
  total_unidades: number;
  total_estimado: number;
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
