export interface PromocionProducto {
  id: number;
  producto_id: number;
  nombre_producto: string;
  precio_producto: number;
}

export interface Promocion {
  id: number;
  nombre: string;
  descripcion: string | null;
  tipo: 'porcentaje' | 'monto_fijo';
  valor: number;
  fecha_inicio: string;
  fecha_fin: string;
  activo: boolean;
  total_productos: number;
  productos: PromocionProducto[];
}

export interface PromocionCreate {
  nombre: string;
  descripcion?: string;
  tipo: 'porcentaje' | 'monto_fijo';
  valor: number;
  fecha_inicio: string;
  fecha_fin: string;
  producto_ids: number[];
}

export interface PromocionUpdate {
  nombre?: string;
  descripcion?: string;
  tipo?: 'porcentaje' | 'monto_fijo';
  valor?: number;
  fecha_inicio?: string;
  fecha_fin?: string;
  activo?: boolean;
}
