import { DatePipe } from '@angular/common';
import { Component, computed, inject } from '@angular/core';
import { OfflineSyncService } from '../../services/offline-sync.service';
import { IconComponent } from '../icon/icon';

/**
 * Aviso "Información desactualizada" (CU8): aparece solo si el catálogo guardado en este dispositivo tiene más de
 * 24 horas sin actualizarse. Se pone en las pantallas que muestran ese catálogo guardado (catálogo y TPV).
 */
@Component({
  selector: 'app-catalogo-desactualizado',
  standalone: true,
  imports: [IconComponent, DatePipe],
  template: `
    @if (sync.catalogoDesactualizado()) {
      <div class="aviso" role="status" aria-live="polite">
        <app-icon name="alert-circle" [size]="20" />
        <div class="texto">
          <strong>Información desactualizada</strong>
          <span>La información puede estar desactualizada. Conéctate a internet para actualizar.</span>
          @if (descargadoEn(); as fecha) {
            <small>Última actualización: {{ antiguedad() }} ({{ fecha | date: 'dd/MM/yyyy HH:mm' }}).</small>
          }
        </div>
      </div>
    }
  `,
  styles: `
    :host { display: block; }
    .aviso {
      display: flex;
      align-items: flex-start;
      gap: 0.75rem;
      padding: 0.75rem 1.1rem;
      border-radius: var(--radius-md, 8px);
      background: color-mix(in srgb, var(--warning, #b3843f) 18%, var(--bg-card, #fffbf3));
      border: 1px solid var(--warning, #b3843f);
      color: var(--text-primary, inherit);
      font-size: 0.92rem;
    }
    .texto { display: flex; flex-direction: column; gap: 0.15rem; }
    small { color: var(--text-secondary, inherit); }
  `,
})
export class CatalogoDesactualizado {
  sync = inject(OfflineSyncService);

  descargadoEn = computed(() => this.sync.catalogoDescargadoEn());
  antiguedad = computed(() => {
    const fecha = this.sync.catalogoDescargadoEn();
    return fecha ? OfflineSyncService.antiguedadTexto(fecha) : '';
  });
}
