import { Injectable, inject } from '@angular/core';
import { HttpClient, HttpParams } from '@angular/common/http';
import { environment } from '../../../environments/environment';
import {
  Dashboard,
  ProductoMasReservado,
  ReporteGenerativo,
  ReservasPorDia,
  ReservasPorEstado,
  ReservasPorSucursal,
  ResumenReportes,
} from '../models/reporte.model';

@Injectable({ providedIn: 'root' })
export class ReportesService {
  private http = inject(HttpClient);
  private readonly base = `${environment.apiUrl}/reportes`;

  resumen(sucursalId?: number) {
    return this.http.get<ResumenReportes>(`${this.base}/resumen`, {
      params: this.paramsSucursal(sucursalId),
    });
  }

  reservasPorEstado(sucursalId?: number) {
    return this.http.get<ReservasPorEstado[]>(`${this.base}/reservas-por-estado`, {
      params: this.paramsSucursal(sucursalId),
    });
  }

  reservasPorSucursal() {
    return this.http.get<ReservasPorSucursal[]>(`${this.base}/reservas-por-sucursal`);
  }

  productosMasReservados(sucursalId?: number, limit = 10) {
    let params = this.paramsSucursal(sucursalId);
    params = params.set('limit', limit);
    return this.http.get<ProductoMasReservado[]>(`${this.base}/productos-mas-reservados`, { params });
  }

  reservasPorDia(sucursalId?: number, dias = 14) {
    let params = this.paramsSucursal(sucursalId);
    params = params.set('dias', dias);
    return this.http.get<ReservasPorDia[]>(`${this.base}/reservas-por-dia`, { params });
  }

  /** CU15 — todo el dashboard del período en una sola llamada. */
  dashboard(sucursalId: number | undefined, dias: number) {
    return this.http.get<Dashboard>(`${this.base}/dashboard`, {
      params: this.paramsSucursal(sucursalId).set('dias', dias),
    });
  }

  exportar(formato: 'pdf' | 'excel', sucursalId: number | undefined, dias = 30) {
    return this.http.get(`${this.base}/exportar/${formato}`, {
      params: this.paramsSucursal(sucursalId).set('dias', dias),
      responseType: 'blob',
    });
  }

  exportarPdf(sucursalId?: number) {
    return this.exportar('pdf', sucursalId);
  }

  exportarExcel(sucursalId?: number) {
    return this.exportar('excel', sucursalId);
  }

  /** CU14 — pide un reporte redactado (IA o reglas si la IA no está disponible). */
  generarReporte(solicitud: string, sucursalId?: number, dias?: number | null) {
    return this.http.post<ReporteGenerativo>(`${this.base}/generativo`, {
      solicitud,
      sucursal_id: sucursalId ?? null,
      dias: dias ?? null,
    });
  }

  exportarReporteGenerativo(formato: 'pdf' | 'excel', reporte: ReporteGenerativo, sucursalId?: number) {
    return this.http.post(
      `${this.base}/generativo/exportar`,
      {
        formato,
        titulo: reporte.titulo,
        contenido: reporte.contenido,
        periodo_dias: reporte.periodo_dias,
        sucursal_id: sucursalId ?? null,
      },
      { responseType: 'blob' }
    );
  }

  private paramsSucursal(sucursalId?: number): HttpParams {
    let params = new HttpParams();
    if (sucursalId) params = params.set('sucursal_id', sucursalId);
    return params;
  }
}
