import { Injectable, inject } from '@angular/core';
import { HttpClient, HttpParams } from '@angular/common/http';
import { environment } from '../../../environments/environment';
import {
  ChatHistorialItem,
  ChatMensajeResponse,
  ChatReportesResponse,
  ConfiguracionIA,
  ConfiguracionIAPrueba,
  ConfiguracionIAUpdate,
  PerfilPreferencias,
  ProductoRecomendado,
} from '../models/ia.model';

@Injectable({ providedIn: 'root' })
export class IaService {
  private http = inject(HttpClient);
  private readonly base = `${environment.apiUrl}/ia`;

  preferencias() {
    return this.http.get<PerfilPreferencias>(`${this.base}/preferencias`);
  }

  recomendaciones(limit = 8) {
    const params = new HttpParams().set('limit', limit);
    return this.http.get<ProductoRecomendado[]>(`${this.base}/recomendaciones`, { params });
  }

  chat(mensaje: string, historial: ChatHistorialItem[] = []) {
    return this.http.post<ChatMensajeResponse>(`${this.base}/chat`, { mensaje, historial });
  }

  chatReportes(mensaje: string, historial: ChatHistorialItem[] = [], sucursalId?: number) {
    return this.http.post<ChatReportesResponse>(`${this.base}/chat-reportes`, {
      mensaje,
      historial,
      sucursal_id: sucursalId ?? null,
    });
  }

  obtenerConfiguracion() {
    return this.http.get<ConfiguracionIA>(`${this.base}/configuracion`);
  }

  actualizarConfiguracion(data: ConfiguracionIAUpdate) {
    return this.http.put<ConfiguracionIA>(`${this.base}/configuracion`, data);
  }

  probarConfiguracion() {
    return this.http.post<ConfiguracionIAPrueba>(`${this.base}/configuracion/probar`, {});
  }
}
