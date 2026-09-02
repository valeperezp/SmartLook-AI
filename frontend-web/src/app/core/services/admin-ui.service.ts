import { Injectable, signal } from '@angular/core';

/** Estado compartido de la UI del panel admin (ej. sidebar colapsable),
 *  para que el botón en el navbar y el sidebar dentro de AdminLayout usen el mismo estado. */
@Injectable({ providedIn: 'root' })
export class AdminUiService {
  sidebarOpen = signal(true);

  toggleSidebar() {
    this.sidebarOpen.set(!this.sidebarOpen());
  }
}
