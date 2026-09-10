export type Rol = 'cliente' | 'administrador' | 'encargado_sucursal';

export interface Usuario {
  id: number;
  nombre: string;
  email: string;
  rol: Rol;
  sucursal_id?: number | null;
  sucursal_nombre?: string | null;
  activo: boolean;
  creado_en: string;
}

export interface UsuarioCreate {
  nombre: string;
  email: string;
  password: string;
  rol: Rol;
}
