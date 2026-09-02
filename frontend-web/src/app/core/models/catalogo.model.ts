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
