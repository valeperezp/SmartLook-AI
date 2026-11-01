import { Component, inject } from '@angular/core';
import { RouterLink, RouterLinkActive, RouterOutlet } from '@angular/router';
import { IconComponent } from '../../../core/components/icon/icon';
import { AdminUiService } from '../../../core/services/admin-ui.service';

/** Panel del superadmin de la plataforma: empresas contratantes y planes. */
@Component({
  selector: 'app-plataforma-layout',
  standalone: true,
  imports: [RouterLink, RouterLinkActive, RouterOutlet, IconComponent],
  template: `
    <div class="admin-shell">
      @if (adminUi.sidebarOpen()) {
        <div class="sidebar-backdrop" (click)="adminUi.toggleSidebar()"></div>
      }
      <aside class="admin-sidebar" [class.collapsed]="!adminUi.sidebarOpen()">
        <h3>Plataforma</h3>
        <nav>
          <a routerLink="/plataforma" [routerLinkActiveOptions]="{exact: true}" routerLinkActive="active">
            <app-icon name="store" [size]="18" /> <span>Empresas</span>
          </a>
          <a routerLink="/plataforma/planes" routerLinkActive="active">
            <app-icon name="credit-card" [size]="18" /> <span>Planes</span>
          </a>
        </nav>
      </aside>

      <main class="admin-content">
        <router-outlet></router-outlet>
      </main>
    </div>
  `,
  styleUrl: '../../admin/admin-layout/admin-layout.scss',
})
export class PlataformaLayout {
  adminUi = inject(AdminUiService);
}
