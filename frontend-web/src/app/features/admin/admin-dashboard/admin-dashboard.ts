import { Component, OnInit, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { HttpClient } from '@angular/common/http';
import { RouterLink } from '@angular/router';
import { AuthService } from '../../../core/services/auth.service';
import { SucursalesService } from '../../../core/services/sucursales.service';
import { UsuariosService } from '../../../core/services/usuarios.service';
import { ProveedoresService } from '../../../core/services/proveedores.service';
import { CatalogoService } from '../../../core/services/catalogo.service';
import { InventarioService } from '../../../core/services/inventario.service';
import { environment } from '../../../../environments/environment';
import { IconComponent } from '../../../core/components/icon/icon';
import { AlertaStock, MovimientoInventario, ResumenInventario } from '../../../core/models/inventario.model';

@Component({
  selector: 'app-admin-dashboard',
  standalone: true,
  imports: [CommonModule, RouterLink, IconComponent],
  template: `
    <div class="dash-header">
      <h1>{{ saludo() }}, <span class="gradient-text">{{ nombre() }}</span></h1>
      <p>Resumen general de la plataforma</p>
    </div>

    <section class="dash-group">
      <h2>Resumen general</h2>
      <div class="stats-grid">
        <div class="stat-card">
          <div class="stat-icon"><app-icon name="store" [size]="22" /></div>
          <div class="stat-info">
            <strong>{{ totalSucursales() }}</strong>
            <span>Sucursales activas</span>
          </div>
        </div>
        <div class="stat-card">
          <div class="stat-icon"><app-icon name="users" [size]="22" /></div>
          <div class="stat-info">
            <strong>{{ totalUsuarios() }}</strong>
            <span>Usuarios registrados</span>
          </div>
        </div>
        <div class="stat-card">
          <div class="stat-icon"><app-icon name="truck" [size]="22" /></div>
          <div class="stat-info">
            <strong>{{ totalProveedores() }}</strong>
            <span>Proveedores</span>
          </div>
        </div>
        <div class="stat-card">
          <div class="stat-icon"><app-icon name="shirt" [size]="22" /></div>
          <div class="stat-info">
            <strong>{{ totalProductos() }}</strong>
            <span>Productos en catálogo</span>
          </div>
        </div>
        <div class="stat-card">
          <div class="stat-icon" [class.status-ok]="backendStatus() === 'ok'" [class.status-error]="backendStatus() !== 'ok'">
            <app-icon [name]="backendStatus() === 'ok' ? 'check-circle' : 'alert-circle'" [size]="22" />
          </div>
          <div class="stat-info">
            <strong>{{ backendStatus() === 'ok' ? 'Activo' : 'Sin conexión' }}</strong>
            <span>Estado del sistema</span>
          </div>
        </div>
      </div>
    </section>

    <section class="dash-group">
      <h2>Inventario global</h2>
      <div class="stats-grid">
        <div class="stat-card">
          <div class="stat-icon icon-primary"><app-icon name="package" [size]="22" /></div>
          <div class="stat-info">
            <strong>{{ resumen()?.total_disponibles ?? 0 }}</strong>
            <span>Unidades disponibles</span>
          </div>
        </div>
        <div class="stat-card">
          <div class="stat-icon icon-warning"><app-icon name="shirt" [size]="22" /></div>
          <div class="stat-info">
            <strong>{{ resumen()?.total_reservados ?? 0 }}</strong>
            <span>Unidades reservadas</span>
          </div>
        </div>
        <div class="stat-card">
          <div class="stat-icon icon-muted"><app-icon name="check-circle" [size]="22" /></div>
          <div class="stat-info">
            <strong>{{ resumen()?.total_vendidos ?? 0 }}</strong>
            <span>Unidades vendidas</span>
          </div>
        </div>
        <div class="stat-card">
          <div class="stat-icon icon-warning"><app-icon name="alert-circle" [size]="22" /></div>
          <div class="stat-info">
            <strong>{{ resumen()?.productos_stock_bajo ?? 0 }}</strong>
            <span>Alertas de stock bajo</span>
          </div>
        </div>
        <div class="stat-card">
          <div class="stat-icon icon-danger"><app-icon name="alert-circle" [size]="22" /></div>
          <div class="stat-info">
            <strong>{{ resumen()?.productos_agotados ?? 0 }}</strong>
            <span>Artículos agotados</span>
          </div>
        </div>
      </div>
    </section>

    <div class="dashboard-columns">
      <div class="card column-card">
        <div class="column-header">
          <h3>
            <app-icon name="alert-circle" [size]="18" />
            <span>Alertas de reposición ({{ alertas().length }})</span>
          </h3>
          <a routerLink="/admin/inventario" class="link-action">Ver en inventario</a>
        </div>

        @if (alertas().length === 0) {
          <p class="empty-state">No hay alertas de stock bajo en ninguna sucursal. ¡Todo en orden!</p>
        } @else {
          <div class="alerts-list">
            @for (a of alertas().slice(0, 5); track a.inventario_id) {
              <div class="alert-item">
                <div class="alert-info">
                  <strong>{{ a.nombre_producto }}</strong>
                  <span>{{ a.nombre_sucursal }} &bull; Disponibles: <b>{{ a.cantidad_disponible }}</b> (Mínimo: {{ a.stock_minimo }})</span>
                </div>
                <span class="badge" [class.badge-danger]="a.cantidad_disponible === 0" [class.badge-warning]="a.cantidad_disponible > 0">
                  {{ a.cantidad_disponible === 0 ? 'Agotado' : 'Bajo' }}
                </span>
              </div>
            }
          </div>
        }
      </div>

      <div class="card column-card">
        <div class="column-header">
          <h3>
            <app-icon name="truck" [size]="18" />
            <span>Últimos movimientos</span>
          </h3>
          <a routerLink="/admin/inventario" class="link-action">Ver inventario</a>
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
                    {{ m.nombre_sucursal }} &bull; {{ m.cantidad }} un. &bull; {{ m.creado_en | date: 'short' }}
                  </span>
                </div>
              </div>
            }
          </div>
        }
      </div>
    </div>
  `,
  styleUrl: './admin-dashboard.scss',
})
export class AdminDashboard implements OnInit {
  private auth = inject(AuthService);
  private http = inject(HttpClient);
  private sucursalesService = inject(SucursalesService);
  private usuariosService = inject(UsuariosService);
  private proveedoresService = inject(ProveedoresService);
  private catalogoService = inject(CatalogoService);
  private inventarioService = inject(InventarioService);

  backendStatus = signal<'checking' | 'ok' | 'error'>('checking');
  totalSucursales = signal(0);
  totalUsuarios = signal(0);
  totalProveedores = signal(0);
  totalProductos = signal(0);
  resumen = signal<ResumenInventario | null>(null);
  alertas = signal<AlertaStock[]>([]);
  movimientos = signal<MovimientoInventario[]>([]);

  nombre = () => this.auth.currentUser()?.nombre ?? 'Administrador';

  saludo(): string {
    const hora = new Date().getHours();
    if (hora < 12) return 'Buenos días';
    if (hora < 19) return 'Buenas tardes';
    return 'Buenas noches';
  }

  ngOnInit() {
    this.http.get<{ status: string }>(`${environment.apiUrl}/health`).subscribe({
      next: () => this.backendStatus.set('ok'),
      error: () => this.backendStatus.set('error'),
    });

    this.sucursalesService.listar().subscribe({
      next: (data) => this.totalSucursales.set(data.length),
    });

    this.usuariosService.listar().subscribe({
      next: (data) => this.totalUsuarios.set(data.length),
    });

    this.proveedoresService.listar().subscribe({
      next: (data) => this.totalProveedores.set(data.length),
    });

    this.catalogoService.listarProductos().subscribe({
      next: (data) => this.totalProductos.set(data.length),
    });

    this.inventarioService.resumen().subscribe({
      next: (data) => this.resumen.set(data),
    });

    this.inventarioService.alertas().subscribe({
      next: (data) => this.alertas.set(data),
    });

    this.inventarioService.listarMovimientos({ limit: 5 }).subscribe({
      next: (data) => this.movimientos.set(data),
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
