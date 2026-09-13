import { Component, inject } from '@angular/core';
import { RouterLink, RouterLinkActive, RouterOutlet } from '@angular/router';
import { IconComponent } from '../../../core/components/icon/icon';
import { AdminUiService } from '../../../core/services/admin-ui.service';

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
        <h3>Panel Admin</h3>
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
          <a routerLink="/admin/inventario" routerLinkActive="active">
            <app-icon name="package" [size]="18" /> <span>Inventario</span>
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
        <router-outlet></router-outlet>
      </main>
    </div>
  `,
  styleUrl: './admin-layout.scss',
})
export class AdminLayout {
  adminUi = inject(AdminUiService);
}
