import { Component, inject, input } from '@angular/core';
import { OfflineSyncService } from '../../services/offline-sync.service';
import { IconComponent } from '../icon/icon';

/**
 * Banner "Modo Offline": avisa cuando no hay red y tranquiliza al usuario (lo que registre queda guardado en este
 * dispositivo y se envía solo al volver la conexión). Con red muestra cuántas operaciones esperan sincronizarse.
 */
@Component({
  selector: 'app-offline-banner',
  standalone: true,
  imports: [IconComponent],
  template: `
    @if (!sync.online()) {
      <div class="banner" role="status" aria-live="polite">
        <app-icon name="alert-circle" [size]="20" />
        <div class="texto">
          <strong>Modo Offline</strong>
          <span>
            Sin conexión a internet.
            @if (mensaje()) { {{ mensaje() }} }
            Tus operaciones se guardan en este dispositivo y se enviarán solas cuando vuelva la conexión.
          </span>
        </div>
        @if (sync.pendientes() > 0) {
          <span class="contador">{{ sync.pendientes() }} pendiente{{ sync.pendientes() === 1 ? '' : 's' }}</span>
        }
      </div>
    } @else if (sync.pendientes() > 0 || sync.sincronizando()) {
      <div class="banner info" role="status" aria-live="polite">
        <div class="texto">
          <strong>{{ sync.sincronizando() ? 'Sincronizando…' : sync.pendientes() + ' operación(es) pendiente(s) de sincronizar' }}</strong>
          @if (sync.ultimoMensaje()) { <span>{{ sync.ultimoMensaje() }}</span> }
        </div>
      </div>
    }
  `,
  styles: `
    :host { display: block; }
    .banner {
      display: flex;
      align-items: center;
      gap: 0.75rem;
      padding: 0.75rem 1.1rem;
      border-radius: var(--radius-md, 8px);
      background: color-mix(in srgb, var(--warning, #b3843f) 18%, var(--bg-card, #fffbf3));
      border: 1px solid var(--warning, #b3843f);
      color: var(--text-primary, inherit);
      font-size: 0.92rem;
    }
    .banner.info { background: var(--bg-card, #fffbf3); border-color: var(--border-strong, #ccc); }
    .texto { display: flex; flex-direction: column; gap: 0.15rem; flex: 1; }
    .contador {
      white-space: nowrap;
      font-weight: 700;
      padding: 0.2rem 0.65rem;
      border-radius: 999px;
      background: var(--warning, #b3843f);
      color: #fff;
    }
  `,
})
export class OfflineBanner {
  sync = inject(OfflineSyncService);
  /** Frase propia de la pantalla (p. ej. "Puedes seguir cobrando."), se muestra solo sin conexión. */
  mensaje = input<string>('');
}
