import { Component, OnInit, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { EmpresasService } from '../../../core/services/empresas.service';
import { EmpresaDetalle, Suscripcion } from '../../../core/models/empresa.model';
import { UsoBar } from '../../plataforma/shared/uso-bar';

/** CU4 2a — El administrador consulta (solo lectura) la suscripción de su empresa. */
@Component({
  selector: 'app-mi-suscripcion',
  standalone: true,
  imports: [CommonModule, UsoBar],
  template: `
    <div class="page-header">
      <h1>Mi suscripción</h1>
      <p>Plan contratado por tu empresa, sus límites y funcionalidades. Para cambiarlo o renovarlo, contactá al administrador de la plataforma.</p>
    </div>

    @if (empresa(); as e) {
      @if (e.suscripcion; as s) {
        <div class="card resumen">
          <div class="resumen-head">
            <div>
              <span class="eyebrow">{{ e.nombre }}</span>
              <h2>Plan {{ s.plan.nombre }}</h2>
              <p class="muted">
                Desde el {{ s.fecha_inicio | date: 'dd/MM/yyyy' }} ·
                @if (s.fecha_fin) { vence el {{ s.fecha_fin | date: 'dd/MM/yyyy' }} } @else { sin vencimiento }
              </p>
            </div>
            <div class="estado">
              <span class="badge" [ngClass]="clase(s.estado_mostrado)">{{ s.estado_mostrado }}</span>
              @if (e.dias_para_vencer !== null) {
                <p class="dias" [class.alerta]="e.dias_para_vencer <= 7">
                  @if (e.dias_para_vencer >= 0) { {{ e.dias_para_vencer }} día(s) restantes }
                  @else { Venció hace {{ -e.dias_para_vencer }} día(s) }
                </p>
              }
            </div>
          </div>
          <div class="usos">
            <app-uso-bar label="Sucursales activas" [valor]="e.uso.sucursales" />
            <app-uso-bar label="Usuarios (personal)" [valor]="e.uso.usuarios" />
            <app-uso-bar label="Productos activos" [valor]="e.uso.productos" />
          </div>
          <div>
            <h3 class="section-title">Funcionalidades habilitadas</h3>
            <ul class="funcionalidades">
              @for (f of e.funcionalidades; track f.codigo) {
                <li><b>{{ f.nombre }}</b> @if (f.descripcion) { <span class="muted">— {{ f.descripcion }}</span> }</li>
              } @empty {
                <li class="muted">El plan no incluye funcionalidades adicionales.</li>
              }
            </ul>
          </div>
        </div>
      } @else {
        <div class="card"><p class="muted">Tu empresa todavía no tiene un plan asignado.</p></div>
      }

      <h3 class="section-title">Historial</h3>
      <div class="card table-wrap">
        <table class="data-table">
          <thead>
            <tr><th>Plan</th><th>Estado</th><th>Inicio</th><th>Vencimiento</th></tr>
          </thead>
          <tbody>
            @for (s of historial(); track s.id) {
              <tr>
                <td>{{ s.plan.nombre }}</td>
                <td><span class="badge" [ngClass]="clase(s.estado_mostrado)">{{ s.estado_mostrado }}</span></td>
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
    .resumen-head { display: flex; justify-content: space-between; align-items: flex-start; gap: 1rem; flex-wrap: wrap; }
    .resumen-head h2 { margin: 0.2rem 0; font-size: 1.5rem; }
    .eyebrow { font-size: 0.75rem; text-transform: uppercase; letter-spacing: 0.08em; color: var(--text-secondary); }
    .muted { color: var(--text-muted); font-size: 0.85rem; margin: 0; }
    .estado { display: flex; flex-direction: column; align-items: flex-end; gap: 0.35rem; }
    .estado .badge, td .badge { text-transform: capitalize; }
    .dias { margin: 0; font-size: 0.9rem; font-variant-numeric: tabular-nums; color: var(--text-secondary); }
    .dias.alerta { color: var(--warning); font-weight: 600; }
    .usos { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, 200px), 1fr)); gap: 1.25rem; }
    .section-title { font-size: 1.05rem; margin: 0 0 0.75rem; }
    .funcionalidades { margin: 0; padding-left: 1.1rem; display: grid; gap: 0.35rem; font-size: 0.9rem; }
    .table-wrap { overflow-x: auto; }
  `,
})
export class MiSuscripcion implements OnInit {
  private service = inject(EmpresasService);

  empresa = signal<EmpresaDetalle | null>(null);
  historial = signal<Suscripcion[]>([]);

  ngOnInit() {
    this.service.miEmpresa().subscribe((e) => this.empresa.set(e));
    this.service.miHistorial().subscribe((h) => this.historial.set(h));
  }

  clase(estado: string): string {
    return { vigente: 'badge-success', vencida: 'badge-danger', suspendida: 'badge-warning', cancelada: 'badge-danger' }[estado]
      ?? 'badge-muted';
  }
}
