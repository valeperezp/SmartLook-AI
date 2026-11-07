import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { environment } from '../../../environments/environment';
import {
  AccionConflicto,
  ConflictoSync,
  ItemAjuste,
  ResolverConflictoRequest,
  ResolverConflictoResponse,
} from '../models/conflicto-sync.model';

/** Resolución manual de conflictos de sincronización (CU13): lista las ventas `en_conflicto` y aplica la decisión del encargado. */
@Injectable({ providedIn: 'root' })
export class ConflictosSyncService {
  private http = inject(HttpClient);
  private readonly base = `${environment.apiUrl}/sync/conflictos`;

  /** El encargado recibe solo las de su sucursal; el administrador, todas (o las de [sucursalId]). */
  listar(sucursalId?: number | null) {
    const params = sucursalId ? new HttpParams().set('sucursal_id', sucursalId) : undefined;
    return this.http.get<ConflictoSync[]>(this.base, { params });
  }

  /** ANULAR no descuenta stock · AJUSTAR cambia las prendas (verifica y descuenta) · FORZAR descuenta aunque quede negativo. */
  resolver(ventaId: number, accion: AccionConflicto, items?: ItemAjuste[], motivo?: string) {
    const cuerpo: ResolverConflictoRequest = { accion, ...(items ? { items } : {}), ...(motivo ? { motivo } : {}) };
    return this.http.post<ResolverConflictoResponse>(`${this.base}/${ventaId}/resolver`, cuerpo);
  }
}
