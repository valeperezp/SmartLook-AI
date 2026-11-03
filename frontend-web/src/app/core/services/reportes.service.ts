import { Injectable, inject } from '@angular/core';
import { HttpClient, HttpParams } from '@angular/common/http';
import { environment } from '../../../environments/environment';
import {
  CatalogoReportes,
  Dashboard,
  HistorialReporte,
  IntencionReporte,
  ProductoMasReservado,
  ResultadoReporte,
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

  // ---------- CU14: reporte generativo ----------

  catalogo() {
    return this.http.get<CatalogoReportes>(`${this.base}/catalogo`);
  }

  /** La IA interpreta la frase; el backend valida y ejecuta un reporte del catálogo permitido. */
  solicitar(solicitud: string) {
    return this.http.post<ResultadoReporte>(`${this.base}/solicitar`, { solicitud });
  }

  /** Reporte convencional (sin IA) o re-ejecución desde el historial. */
  ejecutar(intencion: IntencionReporte) {
    return this.http.post<ResultadoReporte>(`${this.base}/ejecutar`, intencion);
  }

  historial() {
    return this.http.get<HistorialReporte[]>(`${this.base}/historial`);
  }

  exportarReporte(formato: 'pdf' | 'excel', intencion: IntencionReporte, solicitud?: string | null) {
    return this.http.post(
      `${this.base}/ejecutar/exportar`,
      { formato, intencion, solicitud: solicitud || null },
      { responseType: 'blob' }
    );
  }

  private paramsSucursal(sucursalId?: number): HttpParams {
    let params = new HttpParams();
    if (sucursalId) params = params.set('sucursal_id', sucursalId);
    return params;
  }
}
