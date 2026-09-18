import { Injectable, inject } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { environment } from '../../../environments/environment';
import { Promocion, PromocionCreate, PromocionUpdate } from '../models/promocion.model';

@Injectable({ providedIn: 'root' })
export class PromocionesService {
  private http = inject(HttpClient);
  private readonly base = `${environment.apiUrl}/promociones`;

  listar(soloActivas = false) {
    return this.http.get<Promocion[]>(this.base, { params: { solo_activas: soloActivas } });
  }

  obtener(id: number) {
    return this.http.get<Promocion>(`${this.base}/${id}`);
  }

  crear(data: PromocionCreate) {
    return this.http.post<Promocion>(this.base, data);
  }

  actualizar(id: number, data: PromocionUpdate) {
    return this.http.put<Promocion>(`${this.base}/${id}`, data);
  }

  desactivar(id: number) {
    return this.http.delete<Promocion>(`${this.base}/${id}`);
  }

  reactivar(id: number) {
    return this.http.patch<Promocion>(`${this.base}/${id}/reactivar`, {});
  }

  actualizarProductos(id: number, productoIds: number[]) {
    return this.http.put<Promocion>(`${this.base}/${id}/productos`, { producto_ids: productoIds });
  }
}
