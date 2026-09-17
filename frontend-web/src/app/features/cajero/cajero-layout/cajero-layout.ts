import { Component, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterLink, RouterLinkActive, RouterOutlet } from '@angular/router';
import { IconComponent } from '../../../core/components/icon/icon';
import { AuthService } from '../../../core/services/auth.service';

@Component({
  selector: 'app-cajero-layout',
  standalone: true,
  imports: [CommonModule, RouterLink, RouterLinkActive, RouterOutlet, IconComponent],
  template: `
    <div class="cajero-shell">
      <aside class="cajero-sidebar">
        <div class="sidebar-header">
          <div class="brand-title">
            <app-icon name="store" [size]="20" />
            <span>Punto de Venta</span>
          </div>
          <span class="badge-role">Cajero TPV</span>
        </div>

        @if (user()) {
          <div class="user-chip">
            <div class="user-avatar">
              <app-icon name="user" [size]="16" />
            </div>
            <div class="user-meta">
              <strong>{{ user()?.nombre }}</strong>
              <span>{{ user()?.sucursal_nombre || ('Sucursal #' + (user()?.sucursal_id || '1')) }}</span>
            </div>
          </div>
        }

        <nav>
          <span class="nav-group">Operaciones</span>
          <a routerLink="/cajero/ventas" routerLinkActive="active">
            <app-icon name="tag" [size]="18" /> <span>Nueva Venta</span>
          </a>
          <a routerLink="/cajero/ventas-hoy" routerLinkActive="active">
            <app-icon name="calendar" [size]="18" /> <span>Mis Ventas</span>
          </a>
        </nav>

        <div class="sidebar-footer">
          <button type="button" class="btn-logout" (click)="logout()">
            <span>Cerrar sesión</span>
          </button>
        </div>
      </aside>

      <main class="cajero-content">
        <router-outlet></router-outlet>
      </main>
    </div>
  `,
  styleUrl: './cajero-layout.scss',
})
export class CajeroLayout {
  private auth = inject(AuthService);
  user = this.auth.currentUser;

  logout() {
    this.auth.logout();
  }
}
