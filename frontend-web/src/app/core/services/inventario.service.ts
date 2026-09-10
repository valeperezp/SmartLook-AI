import { Injectable, inject } from '@angular/core';
import { HttpClient, HttpParams } from '@angular/common/http';
import { environment } from '../../../environments/environment';
import {
  AlertaStock,
  FiltrosInventario,
  InventarioItem,
  MovimientoInventario,
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

  crearMovimiento(data: {
    inventario_id: number;
    tipo: 'entrada' | 'salida';
    cantidad: number;
    motivo?: string;
  }) {
    return this.http.post<MovimientoInventario>(`${this.base}/movimientos`, data);
  }

  ajustarStock(data: {
    inventario_id: number;
    cantidad?: number;
    nueva_cantidad?: number;
    motivo?: string;
  }) {
    const payload = {
      inventario_id: data.inventario_id,
      nueva_cantidad: data.nueva_cantidad ?? data.cantidad ?? 0,
      motivo: data.motivo,
    };
    return this.http.post<InventarioItem>(`${this.base}/ajuste`, payload);
  }

  actualizarStockMinimo(inventarioId: number, stock_minimo: number) {
    return this.http.patch<InventarioItem>(
      `${this.base}/${inventarioId}/stock-minimo`,
      { stock_minimo }
    );
  }

  miSucursal() {
    return this.http.get<InventarioItem[]>(`${this.base}/mi-sucursal`);
  }

  listarMovimientos(filtros: { tipo?: string; limite?: number; limit?: number } = {}) {
    let params = new HttpParams();
    if (filtros.tipo) params = params.set('tipo', filtros.tipo);
    const lim = filtros.limit ?? filtros.limite;
    if (lim) {
      params = params.set('limit', lim);
    }
    return this.http.get<MovimientoInventario[]>(`${this.base}/movimientos`, { params });
  }
}
