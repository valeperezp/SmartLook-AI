import { Injectable, inject } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { environment } from '../../../environments/environment';

export interface PagoPublico {
  id: number;
  venta_id: number;
  monto: number;
  monto_formateado: string;
  estado: string;
  nombre_sucursal: string | null;
  ya_tiene_comprobante: boolean;
}

export interface ComprobantePublicoResponse {
  id: number;
  venta_id: number;
  monto: number;
  estado: string;
  mensaje: string;
}

@Injectable({ providedIn: 'root' })
export class PagosPublicosService {
  private http = inject(HttpClient);
  private readonly base = `${environment.apiUrl}/pagos`;

  obtener(pagoId: number) {
    return this.http.get<PagoPublico>(`${this.base}/${pagoId}/publico`);
  }

  subirComprobante(pagoId: number, archivo: File) {
    const formData = new FormData();
    formData.append('archivo', archivo);
    return this.http.post<ComprobantePublicoResponse>(
      `${this.base}/${pagoId}/comprobante-publico`,
      formData
    );
  }
}
