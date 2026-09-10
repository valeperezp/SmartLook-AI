import { Injectable, inject } from '@angular/core';
import { HttpClient, HttpParams } from '@angular/common/http';
import { environment } from '../../../environments/environment';
import {
  AlertaStock,
  FiltrosInventario,
  InventarioItem,
  ResumenInventario,
} from '../models/inventario.model';

@Injectable({ providedIn: 'root' })
export class InventarioService {
  private http = inject(HttpClient);
  private readonly base = `${environment.apiUrl}/inventario`;

  listar(filtros: FiltrosInventario = {}) {
    let params = new HttpParams();
    if (filtros.sucursal_id) params = params.set('sucursal_id', filtros.sucursal_id);
    if (filtros.producto_id) params = params.set('producto_id', filtros.producto_id);
    if (filtros.categoria_id) params = params.set('categoria_id', filtros.categoria_id);
    if (filtros.talla_id) params = params.set('talla_id', filtros.talla_id);
    if (filtros.color_id) params = params.set('color_id', filtros.color_id);
    if (filtros.solo_disponibles) params = params.set('solo_disponibles', 'true');
    if (filtros.solo_agotados) params = params.set('solo_agotados', 'true');
    return this.http.get<InventarioItem[]>(this.base, { params });
  }

  resumen() {
    return this.http.get<ResumenInventario>(`${this.base}/resumen`);
  }

  alertas() {
    return this.http.get<AlertaStock[]>(`${this.base}/alertas`);
  }

  porSucursal(sucursalId: number) {
    return this.http.get<InventarioItem[]>(`${this.base}/sucursal/${sucursalId}`);
  }

  porProducto(productoId: number) {
    return this.http.get<InventarioItem[]>(`${this.base}/producto/${productoId}`);
  }
}
