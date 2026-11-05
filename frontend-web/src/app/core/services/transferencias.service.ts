import { Injectable, inject } from '@angular/core';
import { HttpClient, HttpParams } from '@angular/common/http';
import { environment } from '../../../environments/environment';
import { InventarioItem } from '../models/inventario.model';
import {
  AccionTransferencia,
  DisponibilidadTransferencia,
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

  /** Sucursales de la empresa que tienen existencia de la prenda (paso 2). */
  disponibilidad(productoId: number) {
    return this.http.get<DisponibilidadTransferencia[]>(`${this.base}/disponibilidad`, {
      params: new HttpParams().set('producto_id', productoId),
    });
  }

  stockOrigen(sucursalId: number) {
    return this.http.get<InventarioItem[]>(`${this.base}/stock-origen`, {
      params: new HttpParams().set('sucursal_id', sucursalId),
    });
  }

  crear(data: TransferenciaCreate) {
    return this.http.post<Transferencia>(this.base, data);
  }

  ejecutar(
    id: number,
    accion: AccionTransferencia,
    comentario?: string | null,
    recibidas: { item_id: number; cantidad_recibida: number }[] = [],
  ) {
    return this.http.post<Transferencia>(`${this.base}/${id}/${accion}`, { comentario: comentario || null, recibidas });
  }
}
