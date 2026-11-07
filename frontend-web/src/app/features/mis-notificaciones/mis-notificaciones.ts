import { DatePipe } from '@angular/common';
import { Component, OnInit, inject } from '@angular/core';
import { RouterLink } from '@angular/router';
import { IconComponent } from '../../core/components/icon/icon';
import { AvisosStockService } from '../../core/services/avisos-stock.service';

/** CU16 — "Mis notificaciones": las prendas que el cliente esperaba y ya llegaron, y las que todavía espera. */
@Component({
  selector: 'app-mis-notificaciones',
  standalone: true,
  imports: [DatePipe, RouterLink, IconComponent],
  template: `
    <div class="pagina">
      <header>
        <h1><app-icon name="sparkles" [size]="22" /> Mis notificaciones</h1>
        <p class="muted">Te avisamos cuando llega la prenda que estabas esperando.</p>
      </header>

      @if (avisos.notificaciones().length === 0) {
        <p class="vacio" data-testid="sin-avisos">Todavía no llegó nada de lo que esperas.</p>
      } @else {
        <ul class="lista" aria-label="Prendas que ya llegaron">
          @for (n of avisos.notificaciones(); track n.id) {
            <li class="aviso" [class.nuevo]="nuevos.has(n.id)">
              <app-icon name="check-circle" [size]="20" />
              <div>
                <strong>¡Llegó {{ n.descripcion }}!</strong>
                <span class="muted">
                  {{ n.nombre_sucursal ? 'En ' + n.nombre_sucursal + ' · ' : '' }}{{ n.notificado_en | date: 'dd/MM/yyyy HH:mm' }}
                </span>
              </div>
              @if (nuevos.has(n.id)) {
                <span class="etiqueta">Nuevo</span>
              }
            </li>
          }
        </ul>
        <a routerLink="/" class="btn-primary ver-catalogo">Ver el catálogo</a>
      }

      @if (esperando().length > 0) {
        <h2>Esperando</h2>
        <ul class="lista" aria-label="Prendas que todavía esperas">
          @for (e of esperando(); track e.id) {
            <li class="aviso espera">
              <app-icon name="clock" [size]="18" />
              <div>
                <strong>{{ e.descripcion }}</strong>
                <span class="muted">Te avisaremos cuando llegue</span>
              </div>
            </li>
          }
        </ul>
      }
      @if (avisos.pendientesLocales().length > 0) {
        <h2>Pendientes de enviar</h2>
        <ul class="lista" aria-label="Avisos guardados sin conexión">
          @for (p of avisos.pendientesLocales(); track p.uuid) {
            <li class="aviso espera">
              <app-icon name="alert-circle" [size]="18" />
              <div>
                <strong>{{ p.nombre_producto }}</strong>
                <span class="muted">Guardado sin conexión: se enviará al volver la red</span>
              </div>
            </li>
          }
        </ul>
      }
    </div>
  `,
  styles: `
    :host { display: block; }
    .pagina { max-width: 720px; margin: 0 auto; padding: 1.5rem 1rem; display: grid; gap: 1rem; }
    h1 { margin: 0; display: flex; align-items: center; gap: 0.5rem; }
    h2 { margin: 0.5rem 0 0; font-size: 1.05rem; }
    .muted { color: var(--text-muted); font-size: 0.82rem; }
    .vacio { color: var(--text-muted); }
    .lista { list-style: none; margin: 0; padding: 0; display: grid; gap: 0.6rem; }
    .aviso {
      display: flex; align-items: center; gap: 0.75rem; padding: 0.8rem 1rem;
      border: 1px solid var(--border-color); border-radius: var(--radius-md); background: var(--bg-card);
    }
    .aviso > div { display: flex; flex-direction: column; gap: 0.15rem; flex: 1; }
    .aviso.nuevo { border-color: var(--primary); }
    .aviso.espera { opacity: 0.85; }
    .etiqueta { font-size: 0.72rem; font-weight: 700; padding: 0.15rem 0.55rem; border-radius: 999px; background: var(--primary); color: #fff; }
    .ver-catalogo { justify-self: start; text-decoration: none; }
  `,
})
export class MisNotificaciones implements OnInit {
  avisos = inject(AvisosStockService);

  /** Los avisos que eran nuevos al abrir la pantalla (se marcan "Nuevo" en esta visita). */
  nuevos = new Set<number>();

  esperando = () => this.avisos.mias().filter((s) => s.estado === 'pendiente');

  async ngOnInit() {
    await this.avisos.refrescar();
    this.nuevos = new Set(this.avisos.notificaciones().filter((n) => !n.visto).map((n) => n.id));
    // El cliente abrió la pantalla: lo que había de nuevo ya lo vio
    await this.avisos.marcarVistas();
  }
}
