import { Component, computed, inject } from '@angular/core';
import { toSignal } from '@angular/core/rxjs-interop';
import { CommonModule } from '@angular/common';
import { NavigationEnd, Router, RouterOutlet, RouterLink } from '@angular/router';
import { filter, map } from 'rxjs';
import { AuthService } from './core/services/auth.service';
import { AdminUiService } from './core/services/admin-ui.service';
import { IconComponent } from './core/components/icon/icon';

@Component({
  selector: 'app-root',
  standalone: true,
  imports: [CommonModule, RouterOutlet, RouterLink, IconComponent],
  templateUrl: './app.html',
  styleUrl: './app.scss',
})
export class App {
  auth = inject(AuthService);
  adminUi = inject(AdminUiService);
  private router = inject(Router);

  private currentUrl = toSignal(
    this.router.events.pipe(
      filter((e): e is NavigationEnd => e instanceof NavigationEnd),
      map((e) => e.urlAfterRedirects)
    ),
    { initialValue: this.router.url }
  );

  /** Las páginas de login/registro tienen su propia marca inmersiva: no duplicar el navbar. */
  hideNavbar = computed(() => {
    const url = this.currentUrl();
    return url.startsWith('/login') || url.startsWith('/registro');
  });

  /** El botón de colapsar módulos solo tiene sentido dentro del panel admin. */
  showSidebarToggle = computed(() => this.currentUrl().startsWith('/admin'));

  logout() {
    this.auth.logout();
  }
}
