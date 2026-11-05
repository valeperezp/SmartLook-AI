import { Injectable, inject } from '@angular/core';
import { HttpClient, HttpParams } from '@angular/common/http';
import { environment } from '../../../environments/environment';
import {
  AsignarPlan,
  EmpresaCreada,
  EmpresaCreate,
  EmpresaDetalle,
  EmpresaUpdate,
  EntradaBitacora,
  EstadoSuscripcion,
  Funcionalidad,
  Plan,
  PlanCreate,
  Suscripcion,
} from '../models/empresa.model';

/** Empresas (CU2), planes (CU3), suscripciones (CU4) y bitácora. */
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

  listarFuncionalidades() {
    return this.http.get<Funcionalidad[]>(`${this.api}/planes/funcionalidades`);
  }

  crearPlan(data: PlanCreate) {
    return this.http.post<Plan>(`${this.api}/planes`, data);
  }

  actualizarPlan(id: number, data: Partial<PlanCreate> & { activo?: boolean }) {
    return this.http.put<Plan>(`${this.api}/planes/${id}`, data);
  }

  desactivarPlan(id: number) {
    return this.http.post<Plan>(`${this.api}/planes/${id}/desactivar`, {});
  }

  eliminarPlan(id: number) {
    return this.http.delete<void>(`${this.api}/planes/${id}`);
  }

  // ---------- Empresas (superadmin) ----------
  listar() {
    return this.http.get<EmpresaDetalle[]>(`${this.api}/empresas`);
  }

  crear(data: EmpresaCreate) {
    return this.http.post<EmpresaCreada>(`${this.api}/empresas`, data);
  }

  actualizar(id: number, data: EmpresaUpdate) {
    return this.http.put<EmpresaDetalle>(`${this.api}/empresas/${id}`, data);
  }

  suspender(id: number) {
    return this.http.post<EmpresaDetalle>(`${this.api}/empresas/${id}/suspender`, {});
  }

  reactivar(id: number) {
    return this.http.post<EmpresaDetalle>(`${this.api}/empresas/${id}/reactivar`, {});
  }

  historial(id: number) {
    return this.http.get<Suscripcion[]>(`${this.api}/empresas/${id}/suscripciones`);
  }

  asignarPlan(id: number, data: AsignarPlan) {
    return this.http.post<EmpresaDetalle>(`${this.api}/empresas/${id}/suscripcion`, data);
  }

  renovar(id: number) {
    return this.http.post<EmpresaDetalle>(`${this.api}/empresas/${id}/suscripcion/renovar`, {});
  }

  cambiarEstado(id: number, estado: Exclude<EstadoSuscripcion, 'reemplazada'>) {
    return this.http.patch<EmpresaDetalle>(`${this.api}/empresas/${id}/suscripcion`, { estado });
  }

  // ---------- Pública (login) ----------
  empresaPublica(slug: string) {
    return this.http.get<{ nombre: string; slug: string }>(`${this.api}/empresas/publica/${slug}`);
  }

  // ---------- Mi empresa (administrador, solo consulta) ----------
  miEmpresa() {
    return this.http.get<EmpresaDetalle>(`${this.api}/mi-empresa`);
  }

  miHistorial() {
    return this.http.get<Suscripcion[]>(`${this.api}/mi-empresa/suscripciones`);
  }

  // ---------- Bitácora ----------
  bitacora(accion?: string) {
    let params = new HttpParams().set('limite', 300);
    if (accion) params = params.set('accion', accion);
    return this.http.get<EntradaBitacora[]>(`${this.api}/bitacora`, { params });
  }
}
