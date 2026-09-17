import { Injectable, inject } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { environment } from '../../../environments/environment';
import { Venta, VentaPresencialCreate } from '../models/venta.model';

@Injectable({ providedIn: 'root' })
export class VentasService {
  private http = inject(HttpClient);
  private readonly base = `${environment.apiUrl}/ventas`;

  crearVentaPresencial(data: VentaPresencialCreate) {
    return this.http.post<Venta>(this.base, data);
  }

  obtener(id: number) {
    return this.http.get<Venta>(`${this.base}/${id}`);
  }

  listarPorSucursal(sucursalId: number) {
    return this.http.get<Venta[]>(`${this.base}/sucursal/${sucursalId}`);
  }

  listarTodas() {
    return this.http.get<Venta[]>(this.base);
  }
}
