import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { environment } from '../../../environments/environment';
import { Suscripcion, SuscripcionCreate } from '../models/suscripcion.model';

/** "Avísame cuando llegue" (CU16) contra el backend. */
@Injectable({ providedIn: 'root' })
export class SuscripcionesService {
  private http = inject(HttpClient);
  private readonly base = `${environment.apiUrl}/suscripciones`;

  suscribirse(data: SuscripcionCreate) {
    return this.http.post<Suscripcion>(this.base, data);
  }

  /** Todas las suscripciones del cliente (pendientes y ya notificadas). */
  mias() {
    return this.http.get<Suscripcion[]>(`${this.base}/mias`);
  }

  /** Los avisos: prendas que esperaba y que ya llegaron (`estado = notificado`). */
  misNotificaciones(soloNuevas = false) {
    const params = soloNuevas ? new HttpParams().set('solo_nuevas', true) : undefined;
    return this.http.get<Suscripcion[]>(`${this.base}/mis-notificaciones`, { params });
  }

  marcarVistas() {
    return this.http.post<{ marcadas: number }>(`${this.base}/marcar-vistas`, {});
  }
}
