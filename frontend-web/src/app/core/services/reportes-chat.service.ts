import { Injectable, signal } from '@angular/core';

/**
 * Puente entre la página de Reportes y el widget flotante del asistente de IA:
 * el botón "Reporte dinámico (IA)" de esa página abre el mismo widget global
 * (montado una sola vez en app.html) y le pasa el filtro de sucursal ya
 * seleccionado, en vez de duplicar la lógica del chat dentro de la página.
 */
@Injectable({ providedIn: 'root' })
export class ReportesChatService {
  abierto = signal(false);
  sucursalId = signal<number | undefined>(undefined);

  abrir(sucursalId?: number) {
    this.sucursalId.set(sucursalId);
    this.abierto.set(true);
  }

  cerrar() {
    this.abierto.set(false);
  }

  toggle() {
    this.abierto.update((v) => !v);
  }
}
