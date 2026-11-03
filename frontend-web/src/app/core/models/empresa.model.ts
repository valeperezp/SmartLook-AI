export interface Plan {
  id: number;
  nombre: string;
  descripcion?: string | null;
  precio_mensual: number | string;
  /** null = ilimitado */
  max_sucursales: number | null;
  max_usuarios: number | null;
  max_productos: number | null;
  /** RN-05: reportes generativos y analítica con ML */
  incluye_ia: boolean;
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
  /** RF-22: logotipo de los reportes exportados */
  logo_url?: string | null;
  activa: boolean;
  creado_en?: string | null;
}

export interface EmpresaDetalle extends Empresa {
  suscripcion: Suscripcion | null;
  suscripcion_vigente: boolean;
  uso: UsoEmpresa;
  /** RN-08: negativo = ya venció; null = sin vencimiento */
  dias_para_vencer: number | null;
  aviso_vencimiento: boolean;
  /** RN-06: suscripción vencida, solo consulta */
  solo_lectura: boolean;
}

export interface EmpresaCreate {
  nombre: string;
  slug: string;
  nit?: string | null;
  email?: string | null;
  telefono?: string | null;
  direccion?: string | null;
  logo_url?: string | null;
  plan_id: number;
  fecha_fin?: string | null;
  administrador: { nombre: string; email: string; password: string };
}

export type EmpresaUpdate = Partial<Omit<Empresa, 'id' | 'slug' | 'creado_en'>>;
