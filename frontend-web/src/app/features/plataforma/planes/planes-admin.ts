import { Component, OnInit, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { EmpresasService } from '../../../core/services/empresas.service';
import { Plan, PlanCreate } from '../../../core/models/empresa.model';

/** CU3 — Gestionar planes de suscripción (superadmin). */
@Component({
  selector: 'app-planes-admin',
  standalone: true,
  imports: [CommonModule, FormsModule],
  template: `
    <div class="page-header">
      <h1>Planes de suscripción</h1>
      <p>Definí qué incluye cada plan. Dejá un límite vacío para que sea ilimitado.</p>
    </div>

    @if (toast()) {
      <div class="toast-notification" [class.toast-error]="toastIsError()">{{ toast() }}</div>
    }

    <div class="card" style="margin-bottom: 1.5rem;">
      <h3 class="form-title">{{ editandoId() ? 'Editar plan' : 'Nuevo plan' }}</h3>
      <form (ngSubmit)="guardar()">
        <div class="inline-form">
          <div class="form-group">
            <label>Nombre</label>
            <input type="text" [(ngModel)]="form.nombre" name="nombre" required />
          </div>
          <div class="form-group">
            <label>Precio mensual (Bs)</label>
            <input type="number" min="0" step="0.01" [(ngModel)]="form.precio_mensual" name="precio" required />
          </div>
          <div class="form-group">
            <label>Máx. sucursales</label>
            <input type="number" min="1" [(ngModel)]="form.max_sucursales" name="max_sucursales" placeholder="Ilimitado" />
          </div>
          <div class="form-group">
            <label>Máx. usuarios (personal)</label>
            <input type="number" min="1" [(ngModel)]="form.max_usuarios" name="max_usuarios" placeholder="Ilimitado" />
          </div>
          <div class="form-group">
            <label>Máx. productos</label>
            <input type="number" min="1" [(ngModel)]="form.max_productos" name="max_productos" placeholder="Ilimitado" />
          </div>
        </div>
        <label class="check">
          <input type="checkbox" [(ngModel)]="form.incluye_ia" name="incluye_ia" />
          Incluye reportes con IA y analítica con Machine Learning (RN-05)
        </label>
        <div class="form-group" style="margin-top: 1rem;">
          <label>Descripción</label>
          <input type="text" [(ngModel)]="form.descripcion" name="descripcion" />
        </div>
        <div class="inline-form-actions">
          @if (editandoId()) {
            <button type="button" class="btn-secondary" (click)="cancelar()">Cancelar</button>
          }
          <button type="submit" class="btn-primary" [disabled]="guardando()">
            {{ editandoId() ? 'Guardar cambios' : 'Crear plan' }}
          </button>
        </div>
      </form>
    </div>

    <div class="card table-wrap">
      <table class="data-table">
        <thead>
          <tr>
            <th>Plan</th>
            <th class="num">Precio/mes</th>
            <th class="num">Sucursales</th>
            <th class="num">Usuarios</th>
            <th class="num">Productos</th>
            <th>IA</th>
            <th>Estado</th>
            <th>Acciones</th>
          </tr>
        </thead>
        <tbody>
          @for (p of planes(); track p.id) {
            <tr>
              <td>
                <b>{{ p.nombre }}</b>
                @if (p.descripcion) { <div class="muted">{{ p.descripcion }}</div> }
              </td>
              <td class="num">Bs {{ p.precio_mensual | number: '1.2-2' }}</td>
              <td class="num">{{ p.max_sucursales ?? '∞' }}</td>
              <td class="num">{{ p.max_usuarios ?? '∞' }}</td>
              <td class="num">{{ p.max_productos ?? '∞' }}</td>
              <td>{{ p.incluye_ia ? 'Sí' : 'No' }}</td>
              <td>
                <span class="badge" [class.badge-success]="p.activo" [class.badge-muted]="!p.activo">
                  {{ p.activo ? 'Activo' : 'Inactivo' }}
                </span>
              </td>
              <td class="acciones">
                <button class="btn-secondary" (click)="editar(p)">Editar</button>
                @if (p.activo) {
                  <button class="btn-danger" (click)="desactivar(p)">Desactivar</button>
                } @else {
                  <button class="btn-secondary" (click)="reactivar(p)">Reactivar</button>
                }
              </td>
            </tr>
          } @empty {
            <tr><td colspan="8" class="muted">Todavía no hay planes.</td></tr>
          }
        </tbody>
      </table>
    </div>
  `,
  styles: `
    .form-title { font-size: 1rem; margin-bottom: 1rem; }
    .muted { color: var(--text-muted); font-size: 0.8rem; }
    .num { text-align: right; font-variant-numeric: tabular-nums; }
    .acciones { display: flex; gap: 0.5rem; flex-wrap: wrap; }
    .table-wrap { overflow-x: auto; }
    .check { display: flex; align-items: center; gap: 0.5rem; margin-top: 1rem; font-size: 0.875rem; }
  `,
})
export class PlanesAdmin implements OnInit {
  private service = inject(EmpresasService);

  planes = signal<Plan[]>([]);
  guardando = signal(false);
  editandoId = signal<number | null>(null);
  toast = signal<string | null>(null);
  toastIsError = signal(false);

  form = this.vacio();

  ngOnInit() {
    this.cargar();
  }

  private vacio(): PlanCreate {
    return { nombre: '', descripcion: '', precio_mensual: 0, max_sucursales: null, max_usuarios: null, max_productos: null, incluye_ia: false };
  }

  cargar() {
    this.service.listarTodosLosPlanes().subscribe((data) => this.planes.set(data));
  }

  /** Un input numérico vacío llega como '' o null: se manda null (= ilimitado). */
  private payload(): PlanCreate {
    const limite = (v: unknown) => (v === '' || v === null || v === undefined ? null : Number(v));
    return {
      ...this.form,
      precio_mensual: Number(this.form.precio_mensual),
      max_sucursales: limite(this.form.max_sucursales),
      max_usuarios: limite(this.form.max_usuarios),
      max_productos: limite(this.form.max_productos),
    };
  }

  guardar() {
    this.guardando.set(true);
    const id = this.editandoId();
    const req = id ? this.service.actualizarPlan(id, this.payload()) : this.service.crearPlan(this.payload());
    req.subscribe({
      next: () => {
        this.guardando.set(false);
        this.mostrarToast(id ? 'Plan actualizado' : 'Plan creado');
        this.cancelar();
        this.cargar();
      },
      error: (err) => {
        this.guardando.set(false);
        this.mostrarToast(err.error?.detail || 'No se pudo guardar el plan', true);
      },
    });
  }

  editar(p: Plan) {
    this.editandoId.set(p.id);
    this.form = {
      nombre: p.nombre,
      descripcion: p.descripcion ?? '',
      precio_mensual: p.precio_mensual,
      max_sucursales: p.max_sucursales,
      max_usuarios: p.max_usuarios,
      max_productos: p.max_productos,
      incluye_ia: p.incluye_ia,
    };
  }

  cancelar() {
    this.editandoId.set(null);
    this.form = this.vacio();
  }

  desactivar(p: Plan) {
    this.service.desactivarPlan(p.id).subscribe({
      next: () => {
        this.mostrarToast(`${p.nombre} ya no se ofrece. Las empresas que lo tienen lo conservan.`);
        this.cargar();
      },
      error: (err) => this.mostrarToast(err.error?.detail || 'No se pudo desactivar', true),
    });
  }

  reactivar(p: Plan) {
    this.service.actualizarPlan(p.id, { activo: true }).subscribe({
      next: () => {
        this.mostrarToast(`${p.nombre} reactivado`);
        this.cargar();
      },
      error: (err) => this.mostrarToast(err.error?.detail || 'No se pudo reactivar', true),
    });
  }

  private mostrarToast(msg: string, isError = false) {
    this.toast.set(msg);
    this.toastIsError.set(isError);
    setTimeout(() => this.toast.set(null), 3500);
  }
}
