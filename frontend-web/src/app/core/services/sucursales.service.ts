import { Injectable, inject } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { environment } from '../../../environments/environment';
import { Sucursal, SucursalCreate } from '../models/sucursal.model';

@Injectable({ providedIn: 'root' })
export class SucursalesService {
  private http = inject(HttpClient);
  private readonly base = `${environment.apiUrl}/sucursales`;

  listar() {
    return this.http.get<Sucursal[]>(this.base);
  }

  crear(data: SucursalCreate) {
    return this.http.post<Sucursal>(this.base, data);
  }

  actualizar(id: number, data: Partial<SucursalCreate>) {
    return this.http.put<Sucursal>(`${this.base}/${id}`, data);
  }

  eliminar(id: number) {
    return this.http.delete<Sucursal>(`${this.base}/${id}`);
  }
}
