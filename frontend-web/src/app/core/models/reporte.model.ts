export interface ReservasPorEstado {
  estado: string;
  cantidad: number;
}

export interface ReservasPorSucursal {
  sucursal_id: number;
  nombre_sucursal: string;
  cantidad_reservas: number;
  total_unidades: number;
}

export interface ProductoMasReservado {
  producto_id: number;
  nombre_producto: string;
  nombre_categoria: string | null;
  total_unidades: number;
  total_reservas: number;
}

export interface ReservasPorDia {
  fecha: string;
  cantidad: number;
}

export interface ResumenReportes {
  total_reservas: number;
  total_unidades_reservadas: number;
  reservas_por_estado: ReservasPorEstado[];
  inventario_disponible: number;
  inventario_reservado: number;
  productos_stock_bajo: number;
  productos_agotados: number;
}
