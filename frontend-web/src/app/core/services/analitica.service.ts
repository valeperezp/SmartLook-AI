import { Injectable, inject } from '@angular/core';
import { HttpClient, HttpParams } from '@angular/common/http';
import { environment } from '../../../environments/environment';
import { Analitica } from '../models/analitica.model';

/** CU15 — Predicción de demanda y segmentación de clientes. */
@Injectable({ providedIn: 'root' })
export class AnaliticaService {
  private http = inject(HttpClient);
  private readonly base = `${environment.apiUrl}/analitica`;

  consultar(sucursalId?: number) {
    let params = new HttpParams();
    if (sucursalId) params = params.set('sucursal_id', sucursalId);
    return this.http.get<Analitica>(this.base, { params });
  }

  entrenar() {
    return this.http.post<Analitica>(`${this.base}/entrenar`, {});
  }
}
