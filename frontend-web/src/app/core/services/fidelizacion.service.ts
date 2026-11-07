import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { environment } from '../../../environments/environment';
import { MisPuntos } from '../models/fidelizacion.model';

/** Puntos de fidelización (CU17): el saldo y la regla "cuánto vale un punto" vienen siempre del backend. */
@Injectable({ providedIn: 'root' })
export class FidelizacionService {
  private http = inject(HttpClient);
  private readonly base = `${environment.apiUrl}/clientes`;

  /** Saldo del cliente con sesión iniciada. */
  misPuntos() {
    return this.http.get<MisPuntos>(`${this.base}/mis-puntos`);
  }

  /** Saldo de un cliente de la misma empresa (para el cajero al cobrar). */
  puntosDeCliente(clienteId: number) {
    return this.http.get<MisPuntos>(`${this.base}/${clienteId}/puntos`);
  }
}
