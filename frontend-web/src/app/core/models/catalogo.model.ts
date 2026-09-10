export interface Categoria {
  id: number;
  nombre: string;
  activo: boolean;
}

export interface Talla {
  id: number;
  nombre: string;
  activo: boolean;
}

export interface Color {
  id: number;
  nombre: string;
  hex?: string;
  activo: boolean;
}

export interface Temporada {
  id: number;
  nombre: string;
  activo: boolean;
}

export interface Coleccion {
  id: number;
  nombre: string;
  temporada_id?: number;
  activo: boolean;
  temporada?: Temporada;
}

export interface Producto {
  id: number;
  nombre: string;
  descripcion?: string;
  precio: number;
  categoria_id: number;
  temporada_id?: number;
  coleccion_id?: number;
  proveedor_id?: number;
  modelo_ar_url?: string;
  activo: boolean;
  categoria: Categoria;
  temporada?: Temporada;
  coleccion?: Coleccion;
  total_disponible?: number;
  sucursales_con_stock?: number;
  estado_global?: 'disponible' | 'bajo' | 'agotado';
}

export interface ProductoCreate {
  nombre: string;
  descripcion?: string;
  precio: number;
  categoria_id: number;
  temporada_id?: number;
  coleccion_id?: number;
  proveedor_id?: number;
}

export interface DisponibilidadTallaColor {
  talla_id: number | null;
  nombre_talla: string | null;
  color_id: number | null;
  nombre_color: string | null;
  cantidad_disponible: number;
}

export interface DisponibilidadSucursal {
  sucursal_id: number;
  nombre_sucursal: string;
  ciudad: string | null;
  total_disponible: number;
  estado: 'disponible' | 'bajo' | 'agotado';
  items: DisponibilidadTallaColor[];
}

export interface ProductoDisponibilidad {
  producto_id: number;
  nombre_producto: string;
  precio: number;
  imagen_url: string | null;
  total_global: number;
  sucursales_con_stock: number;
  disponibilidad: DisponibilidadSucursal[];
}

