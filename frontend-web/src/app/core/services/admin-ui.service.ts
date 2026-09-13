import { Injectable, signal } from '@angular/core';

/** Estado compartido de la UI de los paneles con sidebar (admin, encargado, proveedor),
 *  para que el botón en el navbar y el sidebar de cada layout usen el mismo estado. */
@Injectable({ providedIn: 'root' })
export class AdminUiService {
  // En escritorio el sidebar es estático y no molesta: arranca abierto.
  // En mobile pasa a ser un panel flotante que se superpone al contenido,
  // así que arranca cerrado para no tapar la pantalla apenas se entra.
  sidebarOpen = signal(typeof window === 'undefined' || window.innerWidth > 900);

  toggleSidebar() {
    this.sidebarOpen.set(!this.sidebarOpen());
  }
}
