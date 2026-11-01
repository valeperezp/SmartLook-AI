import { Injectable, inject } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { environment } from '../../../environments/environment';
import {
  EmpresaCreate,
  EmpresaDetalle,
  EmpresaUpdate,
  EstadoSuscripcion,
  Plan,
  PlanCreate,
  Suscripcion,
} from '../models/empresa.model';

/** Empresas (CU2), planes (CU3) y suscripciones (CU4). */
@Injectable({ providedIn: 'root' })
export class EmpresasService {
  private http = inject(HttpClient);
  private readonly api = environment.apiUrl;

  // ---------- Planes ----------
  listarPlanesActivos() {
    return this.http.get<Plan[]>(`${this.api}/planes`);
  }

  listarTodosLosPlanes() {
    return this.http.get<Plan[]>(`${this.api}/planes/todos`);
  }

  crearPlan(data: PlanCreate) {
    return this.http.post<Plan>(`${this.api}/planes`, data);
  }

  actualizarPlan(id: number, data: Partial<Plan>) {
    return this.http.put<Plan>(`${this.api}/planes/${id}`, data);
  }

  desactivarPlan(id: number) {
    return this.http.delete<Plan>(`${this.api}/planes/${id}`);
  }

  // ---------- Empresas (superadmin) ----------
  listar() {
    return this.http.get<EmpresaDetalle[]>(`${this.api}/empresas`);
  }

  crear(data: EmpresaCreate) {
    return this.http.post<EmpresaDetalle>(`${this.api}/empresas`, data);
  }

  actualizar(id: number, data: EmpresaUpdate) {
    return this.http.put<EmpresaDetalle>(`${this.api}/empresas/${id}`, data);
  }

  desactivar(id: number) {
    return this.http.delete<EmpresaDetalle>(`${this.api}/empresas/${id}`);
  }

  historial(id: number) {
    return this.http.get<Suscripcion[]>(`${this.api}/empresas/${id}/suscripciones`);
  }

  asignarPlan(id: number, plan_id: number, fecha_fin: string | null) {
    return this.http.post<EmpresaDetalle>(`${this.api}/empresas/${id}/suscripcion`, { plan_id, fecha_fin });
  }

  cambiarEstado(id: number, estado: Exclude<EstadoSuscripcion, 'reemplazada'>) {
    return this.http.patch<EmpresaDetalle>(`${this.api}/empresas/${id}/suscripcion`, { estado });
  }

  // ---------- Pública (login) ----------
  empresaPublica(slug: string) {
    return this.http.get<{ nombre: string; slug: string }>(`${this.api}/empresas/publica/${slug}`);
  }

  // ---------- Mi empresa (administrador) ----------
  miEmpresa() {
    return this.http.get<EmpresaDetalle>(`${this.api}/mi-empresa`);
  }

  miHistorial() {
    return this.http.get<Suscripcion[]>(`${this.api}/mi-empresa/suscripciones`);
  }

  cambiarMiPlan(plan_id: number) {
    return this.http.post<EmpresaDetalle>(`${this.api}/mi-empresa/suscripcion`, { plan_id });
  }
}
