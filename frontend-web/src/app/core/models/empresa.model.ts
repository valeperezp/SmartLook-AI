/** Funcionalidad que un plan puede habilitar (CU3). */
export interface Funcionalidad {
  id: number;
  codigo: string;
  nombre: string;
  descripcion?: string | null;
}

export interface Plan {
  id: number;
  nombre: string;
  descripcion?: string | null;
  precio_mensual: number | string;
  /** CU4: la fecha de vencimiento se calcula con esta duración. null = sin vencimiento */
  duracion_dias: number | null;
  /** null = ilimitado */
  max_sucursales: number | null;
  max_usuarios: number | null;
  max_productos: number | null;
  /** RN-05 (se mantiene sincronizado con la funcionalidad reportes_ia) */
  incluye_ia: boolean;
  activo: boolean;
  /** Códigos de las funcionalidades habilitadas */
  funcionalidades: string[];
}

export interface PlanCreate {
  nombre: string;
  descripcion?: string | null;
  precio_mensual: number | string;
  duracion_dias: number | null;
  max_sucursales: number | null;
  max_usuarios: number | null;
  max_productos: number | null;
  funcionalidades: string[];
}

export type EstadoSuscripcion = 'activa' | 'suspendida' | 'cancelada' | 'reemplazada';

export interface Suscripcion {
  id: number;
  empresa_id: number;
  plan_id: number;
  estado: EstadoSuscripcion;
  /** vigente, vencida, suspendida, cancelada o cerrada (CU4 2b) */
  estado_mostrado: string;
  fecha_inicio: string;
  fecha_fin: string | null;
  monto_pagado?: number | string | null;
  metodo_pago_simulado?: string | null;
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
  /** Razón social */
  nombre: string;
  slug: string;
  nit?: string | null;
  email?: string | null;
  telefono?: string | null;
  direccion?: string | null;
  /** RF-22: logotipo de los reportes exportados */
  logo_url?: string | null;
  activa: boolean;
  /** activa | suspendida (CU2 2b) */
  estado: string;
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
  funcionalidades: Funcionalidad[];
}

export interface EmpresaCreada extends EmpresaDetalle {
  credenciales: { email: string; password_temporal: string | null };
}

export interface EmpresaCreate {
  nombre: string;
  nit: string;
  email: string;
  telefono?: string | null;
  direccion?: string | null;
  logo_url?: string | null;
  slug?: string | null;
  plan_id?: number | null;
  fecha_inicio?: string | null;
  administrador: { nombre: string; email: string; password?: string | null };
}

export type EmpresaUpdate = Partial<Pick<Empresa, 'nombre' | 'nit' | 'email' | 'telefono' | 'direccion' | 'logo_url'>>;

export type MetodoPago = 'efectivo' | 'transferencia' | 'tarjeta' | 'qr';

export interface AsignarPlan {
  plan_id: number;
  fecha_inicio?: string | null;
  monto_pagado?: number | null;
  metodo_pago_simulado?: MetodoPago;
}

/** Entrada de la bitácora (CU1, CU2, CU3, CU4, CU5, CU6). */
export interface EntradaBitacora {
  id: number;
  empresa_id: number | null;
  nombre_empresa: string | null;
  usuario_id: number | null;
  nombre_usuario: string | null;
  email_usuario: string | null;
  accion: string;
  detalle: string | null;
  ip: string | null;
  creado_en: string;
}
