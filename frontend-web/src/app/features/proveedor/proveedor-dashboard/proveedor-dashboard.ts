import { Component, OnInit, inject, signal, computed } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterLink } from '@angular/router';
import { IconComponent } from '../../../core/components/icon/icon';
import { AuthService } from '../../../core/services/auth.service';
import { CatalogoService } from '../../../core/services/catalogo.service';
import { Producto } from '../../../core/models/catalogo.model';

@Component({
  selector: 'app-proveedor-dashboard',
  standalone: true,
  imports: [CommonModule, RouterLink, IconComponent],
  template: `
    <div class="dash-header">
      <div>
        <h1>{{ saludo() }}, <span class="gradient-text">{{ nombre() }}</span></h1>
        <p>Panel de gestión de tus productos y catálogo.</p>
      </div>
      @if (proveedorNombre()) {
        <div class="supplier-pill">
          <app-icon name="package" [size]="16" />
          <span>Proveedor: <b>{{ proveedorNombre() }}</b></span>
        </div>
      }
    </div>

    <!-- KPIs del Proveedor -->
    <div class="stats-grid">
      <div class="stat-card">
        <div class="stat-icon icon-emerald">
          <app-icon name="shirt" [size]="22" />
        </div>
        <div class="stat-info">
          <strong>{{ totalProductos() }}</strong>
          <span>Total de productos</span>
        </div>
      </div>

      <div class="stat-card">
        <div class="stat-icon icon-success">
          <app-icon name="check-circle" [size]="22" />
        </div>
        <div class="stat-info">
          <strong>{{ totalActivos() }}</strong>
          <span>Productos activos</span>
        </div>
      </div>

      <div class="stat-card">
        <div class="stat-icon icon-danger">
          <app-icon name="alert-circle" [size]="22" />
        </div>
        <div class="stat-info">
          <strong>{{ totalInactivos() }}</strong>
          <span>Productos inactivos</span>
        </div>
      </div>

      <div class="stat-card">
        <div class="stat-icon icon-warning">
          <app-icon name="tag" [size]="22" />
        </div>
        <div class="stat-info">
          <strong>{{ totalCategorias() }}</strong>
          <span>Categorías cubiertas</span>
        </div>
      </div>
    </div>

    <!-- Accesos Rápidos -->
    <div class="quick-actions">
      <h2>Accesos rápidos</h2>
      <div class="actions-grid">
        <a routerLink="/proveedor/productos" class="action-card">
          <div class="action-icon">
            <app-icon name="shirt" [size]="24" />
          </div>
          <div class="action-text">
            <strong>Mis Productos</strong>
            <p>Ver listado completo, dar de alta nuevos productos y editar existentes.</p>
          </div>
        </a>

        <a routerLink="/proveedor/catalogo" class="action-card">
          <div class="action-icon">
            <app-icon name="package" [size]="24" />
          </div>
          <div class="action-text">
            <strong>Ver Catálogo Global</strong>
            <p>Consultar todo el catálogo público de la plataforma SmartLook-AI.</p>
          </div>
        </a>
      </div>
    </div>

    <!-- Últimos Productos -->
    <div class="card recent-section">
      <div class="section-header">
        <div>
          <h2>Últimos productos</h2>
          <p>Tus 5 productos más recientes registrados en la plataforma</p>
        </div>
        <a routerLink="/proveedor/productos" class="btn-link">Ver todos</a>
      </div>

      @if (cargando()) {
        <div class="loading-state">
          <div class="spinner"></div>
          <p>Cargando información...</p>
        </div>
      } @else if (productos().length === 0) {
        <div class="empty-state">
          <app-icon name="shirt" [size]="36" />
          <p>Aún no tienes productos registrados.</p>
          <a routerLink="/proveedor/productos" class="btn-primary-sm">Dar de alta primer producto</a>
        </div>
      } @else {
        <div class="table-responsive">
          <table class="data-table">
            <thead>
              <tr>
                <th>Producto</th>
                <th>Categoría</th>
                <th>Precio</th>
                <th>Estado</th>
              </tr>
            </thead>
            <tbody>
              @for (p of ultimosProductos(); track p.id) {
                <tr>
                  <td>
                    <strong>{{ p.nombre }}</strong>
                  </td>
                  <td>{{ p.categoria?.nombre || 'General' }}</td>
                  <td class="price-cell">&#36;{{ p.precio | number:'1.2-2' }}</td>
                  <td>
                    <span class="badge" [class.badge-success]="p.activo" [class.badge-danger]="!p.activo">
                      {{ p.activo ? 'Activo' : 'Inactivo' }}
                    </span>
                  </td>
                </tr>
              }
            </tbody>
          </table>
        </div>
      }
    </div>
  `,
  styleUrl: './proveedor-dashboard.scss',
})
export class ProveedorDashboard implements OnInit {
  private auth = inject(AuthService);
  private catalogoService = inject(CatalogoService);

  productos = signal<Producto[]>([]);
  cargando = signal<boolean>(true);

  totalProductos = computed(() => this.productos().length);
  totalActivos = computed(() => this.productos().filter((p) => p.activo).length);
  totalInactivos = computed(() => this.productos().filter((p) => !p.activo).length);
  totalCategorias = computed(
    () => new Set(this.productos().map((p) => p.categoria_id)).size
  );
  ultimosProductos = computed(() => this.productos().slice(0, 5));

  ngOnInit() {
    this.cargando.set(true);
    this.catalogoService.listarMisProductos(true).subscribe({
      next: (data) => {
        this.productos.set(data);
        this.cargando.set(false);
      },
      error: () => {
        this.cargando.set(false);
      },
    });
  }

  saludo(): string {
    const hora = new Date().getHours();
    if (hora < 12) return 'Buenos días';
    if (hora < 19) return 'Buenas tardes';
    return 'Buenas noches';
  }

  nombre(): string {
    return this.auth.currentUser()?.nombre ?? 'Proveedor';
  }

  proveedorNombre(): string {
    return this.auth.currentUser()?.proveedor_nombre ?? '';
  }
}
