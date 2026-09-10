export interface InventarioItem {
  id: number;
  producto_id: number;
  sucursal_id: number;
  talla_id: number | null;
  color_id: number | null;
  cantidad_disponible: number;
  cantidad_reservada: number;
  cantidad_vendida: number;
  stock_minimo: number;
  nombre_producto: string;
  nombre_sucursal: string;
  nombre_talla: string | null;
  nombre_color: string | null;
  estado: 'disponible' | 'bajo' | 'agotado';
}

export interface ResumenInventario {
  total_disponibles: number;
  total_reservados: number;
  total_vendidos: number;
  productos_agotados: number;
  productos_stock_bajo: number;
  total_sucursales: number;
}

export interface AlertaStock {
  inventario_id: number;
  nombre_producto: string;
  nombre_sucursal: string;
  cantidad_disponible: number;
  stock_minimo: number;
  mensaje: string;
}

export interface FiltrosInventario {
  sucursal_id?: number;
  producto_id?: number;
  categoria_id?: number;
  talla_id?: number;
  color_id?: number;
  solo_disponibles?: boolean;
  solo_agotados?: boolean;
}

export interface MovimientoInventario {
  id: number;
  inventario_id: number;
  tipo: 'entrada' | 'salida' | 'ajuste' | 'venta' | 'reserva' | string;
  cantidad: number;
  motivo?: string | null;
  usuario_id?: number | null;
  nombre_usuario?: string | null;
  nombre_producto?: string | null;
  nombre_sucursal?: string | null;
  creado_en: string;
}

export interface MovimientoCreate {
  inventario_id: number;
  tipo: 'entrada' | 'salida';
  cantidad: number;
  motivo?: string;
}

export interface AjusteStockCreate {
  inventario_id: number;
  cantidad?: number;
  nueva_cantidad?: number;
  motivo?: string;
}
