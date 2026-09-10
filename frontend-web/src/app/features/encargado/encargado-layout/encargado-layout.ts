import { Component, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterLink, RouterLinkActive, RouterOutlet } from '@angular/router';
import { IconComponent } from '../../../core/components/icon/icon';
import { AuthService } from '../../../core/services/auth.service';

@Component({
  selector: 'app-encargado-layout',
  standalone: true,
  imports: [CommonModule, RouterLink, RouterLinkActive, RouterOutlet, IconComponent],
  template: `
    <div class="encargado-shell">
      <aside class="encargado-sidebar">
        <div class="sidebar-header">
          <div class="brand-title">
            <app-icon name="store" [size]="20" />
            <span>Mi Sucursal</span>
          </div>
          <span class="badge-role">Encargado</span>
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
          <span class="nav-group">Menú Principal</span>
          <a routerLink="/encargado" [routerLinkActiveOptions]="{ exact: true }" routerLinkActive="active">
            <app-icon name="home" [size]="18" /> <span>Dashboard</span>
          </a>
          <a routerLink="/encargado/inventario" routerLinkActive="active">
            <app-icon name="package" [size]="18" /> <span>Inventario</span>
          </a>
          <a routerLink="/encargado/reservas" routerLinkActive="active">
            <app-icon name="calendar" [size]="18" /> <span>Reservas</span>
          </a>
          <a routerLink="/encargado/movimientos" routerLinkActive="active">
            <app-icon name="truck" [size]="18" /> <span>Movimientos</span>
          </a>
        </nav>

        <div class="sidebar-footer">
          <button type="button" class="btn-logout" (click)="logout()">
            <span>Cerrar sesión</span>
          </button>
        </div>
      </aside>

      <main class="encargado-content">
        <router-outlet></router-outlet>
      </main>
    </div>
  `,
  styleUrl: './encargado-layout.scss',
})
export class EncargadoLayout {
  private auth = inject(AuthService);
  user = this.auth.currentUser;

  logout() {
    this.auth.logout();
  }
}
