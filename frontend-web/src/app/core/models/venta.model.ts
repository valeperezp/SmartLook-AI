export interface VentaItem {
  id: number;
  producto_id: number;
  talla_id: number | null;
  color_id: number | null;
  cantidad: number;
  precio_unitario: number;
  nombre_producto: string;
  nombre_talla: string | null;
  nombre_color: string | null;
  subtotal: number;
}

export interface Venta {
  id: number;
  cliente_id: number | null;
  sucursal_id: number;
  cajero_id: number | null;
  canal: 'presencial' | 'online';
  estado: 'pendiente' | 'completada' | 'cancelada';
  total: number;
  creada_en: string;
  nombre_sucursal: string | null;
  nombre_cajero: string | null;
  nombre_cliente: string | null;
  items: VentaItem[];
  total_items: number;
  total_unidades: number;
}

export interface VentaItemCreate {
  producto_id: number;
  talla_id?: number | null;
  color_id?: number | null;
  cantidad: number;
}

export interface VentaPresencialCreate {
  sucursal_id: number;
  cliente_id?: number | null;
  items: VentaItemCreate[];
}
