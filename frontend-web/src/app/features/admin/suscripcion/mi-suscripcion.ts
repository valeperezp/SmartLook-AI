import { Component, OnInit, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { EmpresasService } from '../../../core/services/empresas.service';
import { EmpresaDetalle, Plan, Suscripcion } from '../../../core/models/empresa.model';
import { UsoBar } from '../../plataforma/shared/uso-bar';
import { estadoSuscripcion } from '../../plataforma/shared/estado-suscripcion';

/** CU4 — El administrador ve el plan de su empresa, cuánto usa y puede cambiar de plan. */
@Component({
  selector: 'app-mi-suscripcion',
  standalone: true,
  imports: [CommonModule, UsoBar],
  template: `
    <div class="page-header">
      <h1>Mi suscripción</h1>
      <p>El plan de tu empresa define cuántas sucursales, usuarios y productos podés tener.</p>
    </div>

    @if (toast()) {
      <div class="toast-notification" [class.toast-error]="toastIsError()">{{ toast() }}</div>
    }

    @if (empresa(); as e) {
      <div class="card resumen">
        <div class="resumen-head">
          <div>
            <span class="eyebrow">{{ e.nombre }}</span>
            <h2>Plan {{ e.suscripcion?.plan?.nombre ?? '—' }}</h2>
            <p class="muted">
              @if (e.suscripcion?.fecha_fin) {
                Vence el {{ e.suscripcion?.fecha_fin | date: 'dd/MM/yyyy' }}
              } @else {
                Sin vencimiento
              }
            </p>
          </div>
          <span class="badge" [ngClass]="estado(e).clase">{{ estado(e).texto }}</span>
        </div>
        <div class="usos">
          <app-uso-bar label="Sucursales activas" [valor]="e.uso.sucursales" />
          <app-uso-bar label="Usuarios (personal)" [valor]="e.uso.usuarios" />
          <app-uso-bar label="Productos activos" [valor]="e.uso.productos" />
        </div>
      </div>

      <h3 class="section-title">Planes disponibles</h3>
      <div class="planes-grid">
        @for (p of planes(); track p.id) {
          <article class="card plan" [class.actual]="p.id === e.suscripcion?.plan_id">
            <h4>{{ p.nombre }}</h4>
            <p class="precio">Bs {{ p.precio_mensual | number: '1.0-2' }}<span>/mes</span></p>
            @if (p.descripcion) { <p class="muted">{{ p.descripcion }}</p> }
            <ul>
              <li>{{ p.max_sucursales ?? 'Sucursales ilimitadas' }}{{ p.max_sucursales ? ' sucursales' : '' }}</li>
              <li>{{ p.max_usuarios ?? 'Usuarios ilimitados' }}{{ p.max_usuarios ? ' usuarios' : '' }}</li>
              <li>{{ p.max_productos ?? 'Productos ilimitados' }}{{ p.max_productos ? ' productos' : '' }}</li>
            </ul>
            @if (p.id === e.suscripcion?.plan_id && e.suscripcion_vigente) {
              <span class="badge badge-success">Tu plan actual</span>
            } @else {
              <button class="btn-primary" [disabled]="cambiando()" (click)="cambiar(p)">Cambiar a {{ p.nombre }}</button>
            }
          </article>
        }
      </div>

      <h3 class="section-title">Historial</h3>
      <div class="card table-wrap">
        <table class="data-table">
          <thead>
            <tr><th>Plan</th><th>Estado</th><th>Desde</th><th>Hasta</th></tr>
          </thead>
          <tbody>
            @for (s of historial(); track s.id) {
              <tr>
                <td>{{ s.plan.nombre }}</td>
                <td>{{ s.estado }}</td>
                <td>{{ s.fecha_inicio | date: 'dd/MM/yyyy' }}</td>
                <td>{{ s.fecha_fin ? (s.fecha_fin | date: 'dd/MM/yyyy') : '—' }}</td>
              </tr>
            }
          </tbody>
        </table>
      </div>
    }
  `,
  styles: `
    .resumen { display: grid; gap: 1.25rem; margin-bottom: 2rem; }
    .resumen-head { display: flex; justify-content: space-between; align-items: flex-start; gap: 1rem; }
    .resumen-head h2 { margin: 0.2rem 0; font-size: 1.5rem; }
    .eyebrow { font-size: 0.75rem; text-transform: uppercase; letter-spacing: 0.08em; color: var(--text-secondary); }
    .muted { color: var(--text-muted); font-size: 0.85rem; margin: 0; }
    .usos { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, 200px), 1fr)); gap: 1.25rem; }
    .section-title { font-size: 1.05rem; margin: 0 0 1rem; }
    .planes-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, 220px), 1fr)); gap: 1rem; margin-bottom: 2rem; }
    .plan { display: flex; flex-direction: column; gap: 0.6rem; }
    .plan.actual { border-color: var(--border-glow); }
    .plan h4 { margin: 0; font-size: 1.1rem; }
    .precio { margin: 0; font-size: 1.6rem; font-weight: 700; font-variant-numeric: tabular-nums; }
    .precio span { font-size: 0.85rem; font-weight: 400; color: var(--text-secondary); }
    .plan ul { margin: 0; padding-left: 1.1rem; font-size: 0.875rem; color: var(--text-secondary); display: grid; gap: 0.25rem; }
    .plan .btn-primary, .plan .badge { margin-top: auto; align-self: flex-start; }
    .table-wrap { overflow-x: auto; }
  `,
})
export class MiSuscripcion implements OnInit {
  private service = inject(EmpresasService);

  empresa = signal<EmpresaDetalle | null>(null);
  planes = signal<Plan[]>([]);
  historial = signal<Suscripcion[]>([]);
  cambiando = signal(false);
  toast = signal<string | null>(null);
  toastIsError = signal(false);
  readonly estado = estadoSuscripcion;

  ngOnInit() {
    this.cargar();
    this.service.listarPlanesActivos().subscribe((p) => this.planes.set(p));
  }

  cargar() {
    this.service.miEmpresa().subscribe((e) => this.empresa.set(e));
    this.service.miHistorial().subscribe((h) => this.historial.set(h));
  }

  cambiar(p: Plan) {
    if (!confirm(`¿Cambiar tu plan a ${p.nombre} (Bs ${p.precio_mensual}/mes)?`)) return;
    this.cambiando.set(true);
    this.service.cambiarMiPlan(p.id).subscribe({
      next: () => {
        this.cambiando.set(false);
        this.mostrarToast(`Listo, ahora tenés el plan ${p.nombre}`);
        this.cargar();
      },
      error: (err) => {
        this.cambiando.set(false);
        this.mostrarToast(err.error?.detail || 'No se pudo cambiar el plan', true);
      },
    });
  }

  private mostrarToast(msg: string, isError = false) {
    this.toast.set(msg);
    this.toastIsError.set(isError);
    setTimeout(() => this.toast.set(null), 4500);
  }
}
