import { Injectable, inject } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { environment } from '../../../environments/environment';
import { Usuario, UsuarioCreate } from '../models/usuario.model';

@Injectable({ providedIn: 'root' })
export class UsuariosService {
  private http = inject(HttpClient);
  private readonly base = `${environment.apiUrl}/usuarios`;

  listar() {
    return this.http.get<Usuario[]>(this.base);
  }

  crear(data: UsuarioCreate) {
    return this.http.post<Usuario>(this.base, data);
  }

  cambiarRol(id: number, rol: string) {
    return this.http.patch<Usuario>(`${this.base}/${id}/rol`, { rol });
  }

  desactivar(id: number) {
    return this.http.delete<Usuario>(`${this.base}/${id}`);
  }
}
