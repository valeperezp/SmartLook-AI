export type Rol = 'cliente' | 'administrador';

export interface Usuario {
  id: number;
  nombre: string;
  email: string;
  rol: Rol;
  activo: boolean;
  creado_en: string;
}

export interface UsuarioCreate {
  nombre: string;
  email: string;
  password: string;
  rol: Rol;
}
