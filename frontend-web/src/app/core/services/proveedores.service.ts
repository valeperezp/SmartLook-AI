import { Injectable, inject } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { environment } from '../../../environments/environment';
import { Proveedor, ProveedorCreate } from '../models/proveedor.model';

@Injectable({ providedIn: 'root' })
export class ProveedoresService {
  private http = inject(HttpClient);
  private readonly base = `${environment.apiUrl}/proveedores`;

  listar() {
    return this.http.get<Proveedor[]>(this.base);
  }

  crear(data: ProveedorCreate) {
    return this.http.post<Proveedor>(this.base, data);
  }

  actualizar(id: number, data: Partial<ProveedorCreate>) {
    return this.http.put<Proveedor>(`${this.base}/${id}`, data);
  }

  eliminar(id: number) {
    return this.http.delete<Proveedor>(`${this.base}/${id}`);
  }
}
