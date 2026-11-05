import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { EmpresasService } from '../../core/services/empresas.service';
import { AuthService } from '../../core/services/auth.service';
import { EntradaBitacora } from '../../core/models/empresa.model';

const ETIQUETAS: Record<string, string> = {
  'sesion.inicio': 'Inicio de sesión',
  'sesion.rechazada': 'Inicio de sesión rechazado',
  'empresa.crear': 'Empresa registrada',
  'empresa.editar': 'Empresa editada',
  'empresa.suspender': 'Empresa suspendida',
  'empresa.reactivar': 'Empresa reactivada',
  'plan.crear': 'Plan creado',
  'plan.editar': 'Plan editado',
  'plan.desactivar': 'Plan desactivado',
  'plan.eliminar': 'Plan eliminado',
  'suscripcion.asignar': 'Plan asignado',
  'suscripcion.cambiar_plan': 'Cambio de plan',
  'suscripcion.renovar': 'Suscripción renovada',
  'suscripcion.estado': 'Estado de suscripción',
  'sucursal.crear': 'Sucursal registrada',
  'sucursal.editar': 'Sucursal editada',
  'sucursal.desactivar': 'Sucursal desactivada',
  'usuario.crear': 'Usuario registrado',
  'usuario.editar': 'Usuario editado',
  'usuario.rol': 'Cambio de rol',
  'usuario.desactivar': 'Usuario desactivado',
  'seguridad.intento_rechazado': 'Intento rechazado',
};

/** Bitácora de acciones: el superadmin ve la de la plataforma y el administrador la de su empresa. */
@Component({
  selector: 'app-bitacora-page',
  standalone: true,
  imports: [CommonModule, FormsModule],
  template: `
    <div class="page-header">
      <h1>Bitácora</h1>
      <p>
        @if (esSuperadmin()) { Acciones sobre empresas, planes y suscripciones de la plataforma. }
        @else { Inicios de sesión y cambios en sucursales y usuarios de tu empresa. }
      </p>
    </div>

    <div class="filtros">
      <select [(ngModel)]="filtro" (ngModelChange)="cargar()" name="filtro">
        <option value="">Todas las acciones</option>
        <option value="sesion">Inicios de sesión</option>
        @if (esSuperadmin()) {
          <option value="empresa.">Empresas</option>
          <option value="plan.">Planes</option>
          <option value="suscripcion.">Suscripciones</option>
        } @else {
          <option value="usuario.">Usuarios</option>
          <option value="sucursal.">Sucursales</option>
          <option value="seguridad.">Seguridad</option>
        }
      </select>
      <span class="muted">{{ entradas().length }} registro(s)</span>
    </div>

    <div class="card table-wrap">
      <table class="data-table">
        <thead>
          <tr><th>Fecha y hora</th><th>Acción</th><th>Detalle</th><th>Usuario</th>@if (esSuperadmin()) {<th>Empresa</th>}</tr>
        </thead>
        <tbody>
          @for (b of entradas(); track b.id) {
            <tr>
              <td class="fecha">{{ b.creado_en | date: 'dd/MM/yyyy HH:mm' }}</td>
              <td><span class="badge" [ngClass]="clase(b.accion)">{{ etiqueta(b.accion) }}</span></td>
              <td>{{ b.detalle }}</td>
              <td>{{ b.nombre_usuario ?? '—' }} @if (b.email_usuario) { <div class="muted">{{ b.email_usuario }}</div> }</td>
              @if (esSuperadmin()) { <td>{{ b.nombre_empresa ?? 'Plataforma' }}</td> }
            </tr>
          } @empty {
            <tr><td [attr.colspan]="esSuperadmin() ? 5 : 4" class="muted">Todavía no hay registros.</td></tr>
          }
        </tbody>
      </table>
    </div>
  `,
  styles: `
    .filtros { display: flex; align-items: center; gap: 1rem; margin-bottom: 1rem; flex-wrap: wrap; }
    .filtros select { max-width: 16rem; }
    .muted { color: var(--text-muted); font-size: 0.8rem; }
    .fecha { white-space: nowrap; font-variant-numeric: tabular-nums; }
    .table-wrap { overflow-x: auto; }
  `,
})
export class BitacoraPage implements OnInit {
  private service = inject(EmpresasService);
  private auth = inject(AuthService);

  entradas = signal<EntradaBitacora[]>([]);
  esSuperadmin = computed(() => this.auth.isSuperadmin());
  filtro = '';

  ngOnInit() {
    this.cargar();
  }

  cargar() {
    this.service.bitacora(this.filtro || undefined).subscribe((data) => this.entradas.set(data));
  }

  etiqueta(accion: string): string {
    return ETIQUETAS[accion] ?? accion;
  }

  clase(accion: string): string {
    if (accion.startsWith('seguridad') || accion === 'sesion.rechazada' || accion.endsWith('suspender')) return 'badge-danger';
    if (accion.startsWith('sesion')) return 'badge-muted';
    if (accion.endsWith('crear') || accion.endsWith('asignar') || accion.endsWith('renovar')) return 'badge-success';
    return 'badge-warning';
  }
}
