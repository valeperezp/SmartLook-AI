import { Injectable, inject } from '@angular/core';
import { HttpClient, HttpParams } from '@angular/common/http';
import { environment } from '../../../environments/environment';
import { Pago, PaymentIntentCreate, PaymentIntentResponse } from '../models/pago.model';

@Injectable({ providedIn: 'root' })
export class PagosService {
  private http = inject(HttpClient);
  private readonly base = `${environment.apiUrl}/pagos`;

  crearIntent(data: PaymentIntentCreate) {
    return this.http.post<PaymentIntentResponse>(`${this.base}/crear-intent`, data);
  }

  confirmar(paymentIntentId: string) {
    return this.http.post<Pago>(`${this.base}/confirmar`, { payment_intent_id: paymentIntentId });
  }

  listarPorVenta(ventaId: number) {
    return this.http.get<Pago[]>(`${this.base}/venta/${ventaId}`);
  }

  crearPagoQR(ventaId: number) {
    return this.http.post<Pago>(`${this.base}/qr`, { venta_id: ventaId });
  }

  obtenerPago(pagoId: number) {
    return this.http.get<Pago>(`${this.base}/${pagoId}`);
  }

  confirmarPagoQR(pagoId: number, aprobar: boolean, motivoRechazo?: string) {
    return this.http.patch<Pago>(`${this.base}/${pagoId}/confirmar-qr`, {
      aprobar,
      motivo_rechazo: motivoRechazo,
    });
  }

  listarPendientesVerificacion(sucursalId?: number) {
    let params = new HttpParams();
    if (sucursalId) params = params.set('sucursal_id', sucursalId);
    return this.http.get<Pago[]>(`${this.base}/pendientes-verificacion`, { params });
  }
}

