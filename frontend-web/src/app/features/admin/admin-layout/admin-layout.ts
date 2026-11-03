import { Component, OnInit, inject, signal } from '@angular/core';
import { EmpresasService } from '../../../core/services/empresas.service';
import { EmpresaDetalle } from '../../../core/models/empresa.model';
import { RouterLink, RouterLinkActive, RouterOutlet } from '@angular/router';
import { IconComponent } from '../../../core/components/icon/icon';
import { AdminUiService } from '../../../core/services/admin-ui.service';
import { AuthService } from '../../../core/services/auth.service';

@Component({
  selector: 'app-admin-layout',
  standalone: true,
  imports: [RouterLink, RouterLinkActive, RouterOutlet, IconComponent],
  template: `
    <div class="admin-shell">
      @if (adminUi.sidebarOpen()) {
        <div class="sidebar-backdrop" (click)="adminUi.toggleSidebar()"></div>
      }
      <aside class="admin-sidebar" [class.collapsed]="!adminUi.sidebarOpen()">
        <h3>{{ auth.currentUser()?.empresa_nombre || 'Panel Admin' }}</h3>
        <nav>
          <a routerLink="/admin" [routerLinkActiveOptions]="{exact: true}" routerLinkActive="active">
            <app-icon name="home" [size]="18" /> <span>Inicio</span>
          </a>
          <span class="nav-group">Gestión</span>
          <a routerLink="/admin/usuarios" routerLinkActive="active">
            <app-icon name="users" [size]="18" /> <span>Usuarios</span>
          </a>
          <a routerLink="/admin/sucursales" routerLinkActive="active">
            <app-icon name="store" [size]="18" /> <span>Sucursales</span>
          </a>
          <a routerLink="/admin/proveedores" routerLinkActive="active">
            <app-icon name="truck" [size]="18" /> <span>Proveedores</span>
          </a>
          <a routerLink="/admin/promociones" routerLinkActive="active">
            <app-icon name="percent" [size]="18" /> <span>Promociones</span>
          </a>
          <a routerLink="/admin/inventario" routerLinkActive="active">
            <app-icon name="package" [size]="18" /> <span>Inventario</span>
          </a>
          <a routerLink="/admin/transferencias" routerLinkActive="active">
            <app-icon name="truck" [size]="18" /> <span>Transferencias</span>
          </a>
          <a routerLink="/admin/reportes" routerLinkActive="active">
            <app-icon name="bar-chart" [size]="18" /> <span>Reportes</span>
          </a>
          <a routerLink="/admin/ia-config" routerLinkActive="active">
            <app-icon name="sparkles" [size]="18" /> <span>Asistente IA</span>
          </a>
          <a routerLink="/admin/suscripcion" routerLinkActive="active">
            <app-icon name="credit-card" [size]="18" /> <span>Mi suscripción</span>
          </a>
          <span class="nav-group">Catálogo maestro</span>
          <a routerLink="/admin/catalogo/productos" routerLinkActive="active">
            <app-icon name="shirt" [size]="18" /> <span>Productos</span>
          </a>
          <a routerLink="/admin/catalogo/categorias" routerLinkActive="active">
            <app-icon name="tag" [size]="18" /> <span>Categorías</span>
          </a>
          <a routerLink="/admin/catalogo/tallas" routerLinkActive="active">
            <app-icon name="ruler" [size]="18" /> <span>Tallas</span>
          </a>
          <a routerLink="/admin/catalogo/colores" routerLinkActive="active">
            <app-icon name="palette" [size]="18" /> <span>Colores</span>
          </a>
          <a routerLink="/admin/catalogo/temporadas" routerLinkActive="active">
            <app-icon name="calendar" [size]="18" /> <span>Temporadas</span>
          </a>
          <a routerLink="/admin/catalogo/colecciones" routerLinkActive="active">
            <app-icon name="package" [size]="18" /> <span>Colecciones</span>
          </a>
        </nav>
      </aside>

      <main class="admin-content">
        @if (empresa(); as e) {
          @if (e.solo_lectura) {
            <div class="banner banner-error" role="alert">
              <app-icon name="alert-circle" [size]="18" />
              <span>
                La suscripción venció hace {{ -e.dias_para_vencer! }} día(s). Solo podés consultar información:
                no se pueden registrar ventas, reservas, sucursales ni usuarios hasta renovarla.
              </span>
              <a routerLink="/admin/suscripcion">Renovar</a>
            </div>
          } @else if (e.aviso_vencimiento) {
            <div class="banner" role="status">
              <app-icon name="clock" [size]="18" />
              <span>
                @if (e.dias_para_vencer === 0) { Tu suscripción vence hoy. }
                @else { Tu suscripción vence en {{ e.dias_para_vencer }} día(s). }
              </span>
              <a routerLink="/admin/suscripcion">Ver suscripción</a>
            </div>
          }
        }
        <router-outlet></router-outlet>
      </main>
    </div>
  `,
  styleUrl: './admin-layout.scss',
  styles: `
    .banner {
      display: flex;
      align-items: center;
      gap: 0.6rem;
      flex-wrap: wrap;
      margin-bottom: 1.25rem;
      padding: 0.75rem 1rem;
      border-radius: var(--radius-md);
      border: 1px solid rgba(179, 132, 63, 0.4);
      background: rgba(179, 132, 63, 0.12);
      color: var(--text-primary);
      font-size: 0.9rem;

      app-icon { color: var(--warning); }
      span { flex: 1; min-width: 14rem; }
      a { font-weight: 600; color: var(--primary); }
    }
    .banner-error {
      border-color: rgba(163, 64, 47, 0.35);
      background: rgba(163, 64, 47, 0.1);
      app-icon { color: var(--danger); }
    }
  `,
})
export class AdminLayout implements OnInit {
  adminUi = inject(AdminUiService);
  auth = inject(AuthService);
  private empresas = inject(EmpresasService);

  /** RN-06 y RN-08: estado de la suscripción para los avisos de vencimiento. */
  empresa = signal<EmpresaDetalle | null>(null);

  ngOnInit() {
    this.empresas.miEmpresa().subscribe({ next: (e) => this.empresa.set(e), error: () => this.empresa.set(null) });
  }
}
