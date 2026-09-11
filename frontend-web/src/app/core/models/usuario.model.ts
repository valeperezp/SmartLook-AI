export type Rol = 'cliente' | 'administrador' | 'encargado_sucursal' | 'proveedor';

export interface Usuario {
  id: number;
  nombre: string;
  email: string;
  rol: Rol;
  sucursal_id?: number | null;
  sucursal_nombre?: string | null;
  proveedor_id?: number | null;
  proveedor_nombre?: string | null;
  activo: boolean;
  creado_en: string;
}

export interface UsuarioCreate {
  nombre: string;
  email: string;
  password: string;
  rol: Rol;
  sucursal_id?: number | null;
  proveedor_id?: number | null;
}

