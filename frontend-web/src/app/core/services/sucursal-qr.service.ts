import { Injectable, inject } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { environment } from '../../../environments/environment';
import { SucursalQR } from '../models/sucursal-qr.model';

@Injectable({ providedIn: 'root' })
export class SucursalQRService {
  private http = inject(HttpClient);
  private readonly base = `${environment.apiUrl}/sucursales`;

  obtener(sucursalId: number) {
    return this.http.get<SucursalQR>(`${this.base}/${sucursalId}/qr`);
  }

  subir(sucursalId: number, archivo: File) {
    const formData = new FormData();
    formData.append('archivo', archivo);
    return this.http.post<SucursalQR>(`${this.base}/${sucursalId}/qr`, formData);
  }

  desactivar(sucursalId: number) {
    return this.http.delete<void>(`${this.base}/${sucursalId}/qr`);
  }
}
