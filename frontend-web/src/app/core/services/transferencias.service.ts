import { Injectable, inject } from '@angular/core';
import { HttpClient, HttpParams } from '@angular/common/http';
import { environment } from '../../../environments/environment';
import { InventarioItem } from '../models/inventario.model';
import {
  AccionTransferencia,
  EstadoTransferencia,
  Transferencia,
  TransferenciaCreate,
} from '../models/transferencia.model';

/** CU19 — Transferencias de stock entre sucursales. */
@Injectable({ providedIn: 'root' })
export class TransferenciasService {
  private http = inject(HttpClient);
  private readonly base = `${environment.apiUrl}/transferencias`;

  listar(estado?: EstadoTransferencia | null) {
    let params = new HttpParams();
    if (estado) params = params.set('estado', estado);
    return this.http.get<Transferencia[]>(this.base, { params });
  }

  stockOrigen(sucursalId: number) {
    return this.http.get<InventarioItem[]>(`${this.base}/stock-origen`, {
      params: new HttpParams().set('sucursal_id', sucursalId),
    });
  }

  crear(data: TransferenciaCreate) {
    return this.http.post<Transferencia>(this.base, data);
  }

  ejecutar(id: number, accion: AccionTransferencia, comentario?: string | null) {
    return this.http.post<Transferencia>(`${this.base}/${id}/${accion}`, { comentario: comentario || null });
  }
}
