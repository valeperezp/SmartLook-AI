import { Injectable, inject } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { environment } from '../../../environments/environment';
import { Reserva, ReservaCreate } from '../models/reserva.model';

@Injectable({ providedIn: 'root' })
export class ReservasService {
  private http = inject(HttpClient);
  private readonly base = `${environment.apiUrl}/reservas`;

  crear(data: ReservaCreate) {
    return this.http.post<Reserva>(this.base, data);
  }

  misReservas() {
    return this.http.get<Reserva[]>(`${this.base}/mis-reservas`);
  }

  obtener(id: number) {
    return this.http.get<Reserva>(`${this.base}/${id}`);
  }

  cancelar(id: number) {
    return this.http.patch<Reserva>(`${this.base}/${id}/cancelar`, {});
  }

  // ===== MÉTODOS PARA ENCARGADO =====

  miSucursal() {
    return this.http.get<Reserva[]>(`${this.base}/mi-sucursal`);
  }

  detalleEncargado(reservaId: number) {
    return this.http.get<Reserva>(`${this.base}/detalle/${reservaId}`);
  }

  cambiarEstado(reservaId: number, nuevoEstado: string) {
    return this.http.patch<Reserva>(
      `${this.base}/${reservaId}/estado?nuevo_estado=${nuevoEstado}`,
      {}
    );
  }
}

