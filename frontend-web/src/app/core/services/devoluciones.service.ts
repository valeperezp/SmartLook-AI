import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { environment } from '../../../environments/environment';
import { DevolucionCreate, DevolucionOut, VentaDevolvible } from '../models/devolucion.model';
import { Reembolso } from '../models/reserva.model';

/** Cambios y devoluciones (CU11). Las reglas (plazo de días, cantidades, stock) las valida SIEMPRE el backend. */
@Injectable({ providedIn: 'root' })
export class DevolucionesService {
  private http = inject(HttpClient);
  private readonly base = `${environment.apiUrl}/devoluciones`;

  /** Busca la venta por número de ticket (`123` o `#123`) o por el UUID / recibo con el que la app móvil la mandó. */
  buscar(texto: string) {
    return this.http.get<VentaDevolvible>(`${this.base}/buscar`, { params: new HttpParams().set('q', texto.trim()) });
  }

  /** Registra el cambio o la devolución. Si el servidor la rechaza (plazo vencido, cantidades, sin stock) responde 400 con el motivo. */
  registrar(data: DevolucionCreate) {
    return this.http.post<DevolucionOut>(this.base, data);
  }

  /** Días que una venta admite cambios y devoluciones en esta empresa. */
  plazoDias() {
    return this.http.get<{ plazo_dias: number }>(`${this.base}/configuracion`);
  }

  /**
   * Reembolso de DINERO de un pedido cancelado (una reserva o una venta): ya se le transfirió al cliente (al QR que subió).
   * El pedido pasa a `reembolsada`. Funciona aunque el cliente no haya subido su QR.
   */
  procesarReembolso(origen: { reserva_id: number } | { venta_id: number }) {
    return this.http.post<Reembolso & { origen: string; nombre_cliente: string | null }>(`${this.base}/reembolsos/procesar`, origen);
  }
}
