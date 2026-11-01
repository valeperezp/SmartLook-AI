import { EmpresaDetalle } from '../../../core/models/empresa.model';

/** Texto y clase de badge para el estado de la suscripción de una empresa. */
export function estadoSuscripcion(e: Pick<EmpresaDetalle, 'suscripcion' | 'suscripcion_vigente'>): {
  texto: string;
  clase: string;
} {
  const s = e.suscripcion;
  if (!s) return { texto: 'Sin plan', clase: 'badge-muted' };
  if (e.suscripcion_vigente) return { texto: 'Vigente', clase: 'badge-success' };
  if (s.estado === 'activa') return { texto: 'Vencida', clase: 'badge-danger' };
  if (s.estado === 'suspendida') return { texto: 'Suspendida', clase: 'badge-warning' };
  return { texto: 'Cancelada', clase: 'badge-danger' };
}
