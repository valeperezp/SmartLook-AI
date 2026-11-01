export interface Plan {
  id: number;
  nombre: string;
  descripcion?: string | null;
  precio_mensual: number | string;
  /** null = ilimitado */
  max_sucursales: number | null;
  max_usuarios: number | null;
  max_productos: number | null;
  activo: boolean;
}

export type PlanCreate = Omit<Plan, 'id' | 'activo'>;

export type EstadoSuscripcion = 'activa' | 'suspendida' | 'cancelada' | 'reemplazada';

export interface Suscripcion {
  id: number;
  empresa_id: number;
  plan_id: number;
  estado: EstadoSuscripcion;
  fecha_inicio: string;
  fecha_fin: string | null;
  creado_en?: string | null;
  plan: Plan;
}

export interface UsoRecurso {
  usados: number;
  limite: number | null;
}

export interface UsoEmpresa {
  sucursales: UsoRecurso;
  usuarios: UsoRecurso;
  productos: UsoRecurso;
}

export interface Empresa {
  id: number;
  nombre: string;
  slug: string;
  nit?: string | null;
  email?: string | null;
  telefono?: string | null;
  direccion?: string | null;
  activa: boolean;
  creado_en?: string | null;
}

export interface EmpresaDetalle extends Empresa {
  suscripcion: Suscripcion | null;
  suscripcion_vigente: boolean;
  uso: UsoEmpresa;
}

export interface EmpresaCreate {
  nombre: string;
  slug: string;
  nit?: string | null;
  email?: string | null;
  telefono?: string | null;
  direccion?: string | null;
  plan_id: number;
  fecha_fin?: string | null;
  administrador: { nombre: string; email: string; password: string };
}

export type EmpresaUpdate = Partial<Omit<Empresa, 'id' | 'slug' | 'creado_en'>>;
