export interface Sucursal {
  id: number;
  nombre: string;
  direccion: string;
  ciudad?: string;
  telefono?: string;
  activa: boolean;
}

export interface SucursalCreate {
  nombre: string;
  direccion: string;
  ciudad?: string;
  telefono?: string;
}
