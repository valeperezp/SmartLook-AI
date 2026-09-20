import { Injectable, inject } from '@angular/core';
import { HttpClient, HttpParams } from '@angular/common/http';
import { environment } from '../../../environments/environment';
import {
  ProductoMasReservado,
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

  exportarPdf(sucursalId?: number) {
    return this.http.get(`${this.base}/exportar/pdf`, {
      params: this.paramsSucursal(sucursalId),
      responseType: 'blob',
    });
  }

  exportarExcel(sucursalId?: number) {
    return this.http.get(`${this.base}/exportar/excel`, {
      params: this.paramsSucursal(sucursalId),
      responseType: 'blob',
    });
  }

  private paramsSucursal(sucursalId?: number): HttpParams {
    let params = new HttpParams();
    if (sucursalId) params = params.set('sucursal_id', sucursalId);
    return params;
  }
}
