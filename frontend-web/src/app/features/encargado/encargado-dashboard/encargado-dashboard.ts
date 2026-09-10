import { Component, OnInit, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterLink } from '@angular/router';
import { IconComponent } from '../../../core/components/icon/icon';
import { AuthService } from '../../../core/services/auth.service';
import { InventarioService } from '../../../core/services/inventario.service';
import {
  AlertaStock,
  MovimientoInventario,
  ResumenInventario,
} from '../../../core/models/inventario.model';

@Component({
  selector: 'app-encargado-dashboard',
  standalone: true,
  imports: [CommonModule, RouterLink, IconComponent],
  template: `
    <div class="dash-header">
      <div>
        <h1>Hola, <span class="gradient-text">{{ user()?.nombre || 'Encargado' }}</span></h1>
        <p>Panel de control operativo de tu sucursal asignada.</p>
      </div>
      <div class="branch-pill">
        <app-icon name="store" [size]="16" />
        <span>Sucursal asignada: <b>{{ user()?.sucursal_nombre || ('#' + (user()?.sucursal_id || '1')) }}</b></span>
      </div>
    </div>

    <!-- KPIs de la Sucursal -->
    <div class="stats-grid">
      <div class="stat-card">
        <div class="stat-icon icon-primary">
          <app-icon name="package" [size]="22" />
        </div>
        <div class="stat-info">
          <strong>{{ resumen()?.total_disponibles ?? 0 }}</strong>
          <span>Unidades disponibles</span>
        </div>
      </div>

      <div class="stat-card">
        <div class="stat-icon icon-warning">
          <app-icon name="shirt" [size]="22" />
        </div>
        <div class="stat-info">
          <strong>{{ resumen()?.total_reservados ?? 0 }}</strong>
          <span>Unidades reservadas</span>
        </div>
      </div>

      <div class="stat-card">
        <div class="stat-icon icon-danger">
          <app-icon name="alert-circle" [size]="22" />
        </div>
        <div class="stat-info">
          <strong>{{ resumen()?.productos_stock_bajo ?? 0 }}</strong>
          <span>Alertas de stock bajo</span>
        </div>
      </div>

      <div class="stat-card">
        <div class="stat-icon icon-muted">
          <app-icon name="tag" [size]="22" />
        </div>
        <div class="stat-info">
          <strong>{{ resumen()?.productos_agotados ?? 0 }}</strong>
          <span>Artículos agotados</span>
        </div>
      </div>
    </div>

    <!-- Acciones Rápidas -->
    <div class="quick-actions">
      <h2>Operaciones rápidas</h2>
      <div class="actions-grid">
        <a routerLink="/encargado/inventario" class="action-card">
          <div class="action-icon">
            <app-icon name="package" [size]="24" />
          </div>
          <div class="action-text">
            <strong>Gestionar Inventario</strong>
            <p>Registrar entradas, salidas de mercancía y conteo físico.</p>
          </div>
        </a>

        <a routerLink="/encargado/movimientos" class="action-card">
          <div class="action-icon">
            <app-icon name="truck" [size]="24" />
          </div>
          <div class="action-text">
            <strong>Historial de Movimientos</strong>
            <p>Auditar todas las entradas, salidas y ajustes de tu sucursal.</p>
          </div>
        </a>
      </div>
    </div>

    <div class="dashboard-columns">
      <!-- Alertas de Stock Bajo -->
      <div class="card column-card">
        <div class="column-header">
          <h3>
            <app-icon name="alert-circle" [size]="18" />
            <span>Alertas de reposición ({{ alertas().length }})</span>
          </h3>
          <a routerLink="/encargado/inventario" class="link-action">Ver en inventario</a>
        </div>

        @if (alertas().length === 0) {
          <p class="empty-state">No hay alertas de stock bajo en este momento. ¡Todo en orden!</p>
        } @else {
          <div class="alerts-list">
            @for (a of alertas(); track a.inventario_id) {
              <div class="alert-item">
                <div class="alert-info">
                  <strong>{{ a.nombre_producto }}</strong>
                  <span>Disponibles: <b>{{ a.cantidad_disponible }}</b> (Mínimo: {{ a.stock_minimo }})</span>
                </div>
                <span class="badge" [class.badge-danger]="a.cantidad_disponible === 0" [class.badge-warning]="a.cantidad_disponible > 0">
                  {{ a.cantidad_disponible === 0 ? 'Agotado' : 'Bajo' }}
                </span>
              </div>
            }
          </div>
        }
      </div>

      <!-- Últimos Movimientos -->
      <div class="card column-card">
        <div class="column-header">
          <h3>
            <app-icon name="truck" [size]="18" />
            <span>Últimos movimientos</span>
          </h3>
          <a routerLink="/encargado/movimientos" class="link-action">Ver todos</a>
        </div>

        @if (movimientos().length === 0) {
          <p class="empty-state">No hay movimientos registrados recientemente.</p>
        } @else {
          <div class="movements-list">
            @for (m of movimientos(); track m.id) {
              <div class="movement-item">
                <span class="badge badge-tipo" [ngClass]="badgeClass(m.tipo)">
                  {{ m.tipo | uppercase }}
                </span>
                <div class="movement-info">
                  <strong>{{ m.nombre_producto }}</strong>
                  <span class="movement-meta">
                    {{ m.cantidad }} un. &bull; {{ m.creado_en | date: 'short' }} &bull; {{ m.nombre_usuario || 'Sistema' }}
                  </span>
                </div>
              </div>
            }
          </div>
        }
      </div>
    </div>
  `,
  styleUrl: './encargado-dashboard.scss',
})
export class EncargadoDashboard implements OnInit {
  private auth = inject(AuthService);
  private inventarioService = inject(InventarioService);

  user = this.auth.currentUser;
  resumen = signal<ResumenInventario | null>(null);
  alertas = signal<AlertaStock[]>([]);
  movimientos = signal<MovimientoInventario[]>([]);

  ngOnInit() {
    this.cargarDatos();
  }

  cargarDatos() {
    this.inventarioService.resumen().subscribe({
      next: (data) => this.resumen.set(data),
      error: (err) => console.error('Error al cargar resumen', err),
    });

    this.inventarioService.alertas().subscribe({
      next: (data) => this.alertas.set(data),
      error: (err) => console.error('Error al cargar alertas', err),
    });

    this.inventarioService.listarMovimientos({ limite: 5 }).subscribe({
      next: (data) => this.movimientos.set(data),
      error: (err) => console.error('Error al cargar movimientos', err),
    });
  }

  badgeClass(tipo: string): string {
    switch (tipo?.toLowerCase()) {
      case 'entrada':
        return 'badge-success';
      case 'salida':
        return 'badge-danger';
      case 'ajuste':
        return 'badge-info';
      default:
        return 'badge-muted';
    }
  }
}
