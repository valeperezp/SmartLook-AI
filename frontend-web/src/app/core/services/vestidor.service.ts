import { Injectable, inject } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { environment } from '../../../environments/environment';

export interface VestidorPrueba {
  imagen_base64: string;
  mime_type: string;
}

@Injectable({ providedIn: 'root' })
export class VestidorService {
  private http = inject(HttpClient);
  private readonly base = `${environment.apiUrl}/vestidor`;

  generarPrueba(productoId: number, foto: File) {
    const formData = new FormData();
    formData.append('producto_id', String(productoId));
    formData.append('foto', foto);
    return this.http.post<VestidorPrueba>(`${this.base}/generar`, formData);
  }
}
