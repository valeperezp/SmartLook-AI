import { Component, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterLink, RouterLinkActive, RouterOutlet } from '@angular/router';
import { IconComponent } from '../../../core/components/icon/icon';
import { AuthService } from '../../../core/services/auth.service';
import { AdminUiService } from '../../../core/services/admin-ui.service';

@Component({
  selector: 'app-proveedor-layout',
  standalone: true,
  imports: [CommonModule, RouterLink, RouterLinkActive, RouterOutlet, IconComponent],
  template: `
    <div class="proveedor-shell">
      @if (ui.sidebarOpen()) {
        <div class="sidebar-backdrop" (click)="ui.toggleSidebar()"></div>
      }
      <aside class="proveedor-sidebar" [class.collapsed]="!ui.sidebarOpen()">
        <div class="sidebar-header">
          <div class="brand-title">
            <app-icon name="package" [size]="20" />
            <span>Panel Proveedor</span>
          </div>
          <span class="badge-role">Proveedor</span>
        </div>

        @if (user()) {
          <div class="user-chip">
            <div class="user-avatar">
              <app-icon name="user" [size]="16" />
            </div>
            <div class="user-meta">
              <strong>{{ user()?.nombre }}</strong>
              <span>{{ user()?.proveedor_nombre || 'Proveedor' }}</span>
            </div>
          </div>
        }

        <nav>
          <span class="nav-group">Menú Principal</span>
          <a routerLink="/proveedor" [routerLinkActiveOptions]="{ exact: true }" routerLinkActive="active">
            <app-icon name="home" [size]="18" /> <span>Inicio</span>
          </a>
          <a routerLink="/proveedor/productos" routerLinkActive="active">
            <app-icon name="shirt" [size]="18" /> <span>Mis Productos</span>
          </a>
          <a routerLink="/proveedor/catalogo" routerLinkActive="active">
            <app-icon name="package" [size]="18" /> <span>Catálogo</span>
          </a>
        </nav>
      </aside>

      <main class="proveedor-content">
        <router-outlet></router-outlet>
      </main>
    </div>
  `,
  styleUrl: './proveedor-layout.scss',
})
export class ProveedorLayout {
  private auth = inject(AuthService);
  ui = inject(AdminUiService);
  user = this.auth.currentUser;
}
