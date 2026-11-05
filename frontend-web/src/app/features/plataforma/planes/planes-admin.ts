import { Component, OnInit, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { EmpresasService } from '../../../core/services/empresas.service';
import { Funcionalidad, Plan, PlanCreate } from '../../../core/models/empresa.model';

/** CU3 — Gestionar planes de suscripción (superadmin). */
@Component({
  selector: 'app-planes-admin',
  standalone: true,
  imports: [CommonModule, FormsModule],
  template: `
    <div class="page-header">
      <h1>Planes de suscripción</h1>
      <p>Límites, duración y funcionalidades de cada plan. Un límite vacío es ilimitado.</p>
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
            <label>Precio referencial (Bs)</label>
            <input type="number" min="0" step="0.01" [(ngModel)]="form.precio_mensual" name="precio" required />
          </div>
          <div class="form-group">
            <label>Duración (días)</label>
            <input type="number" [(ngModel)]="form.duracion_dias" name="duracion" placeholder="Sin vencimiento" />
          </div>
          <div class="form-group">
            <label>Límite de sucursales activas</label>
            <input type="number" [(ngModel)]="form.max_sucursales" name="max_sucursales" placeholder="Ilimitado" />
          </div>
          <div class="form-group">
            <label>Máx. usuarios (personal)</label>
            <input type="number" [(ngModel)]="form.max_usuarios" name="max_usuarios" placeholder="Ilimitado" />
          </div>
          <div class="form-group">
            <label>Máx. productos</label>
            <input type="number" [(ngModel)]="form.max_productos" name="max_productos" placeholder="Ilimitado" />
          </div>
        </div>

        <fieldset class="funcionalidades">
          <legend>Funcionalidades</legend>
          @for (f of funcionalidades(); track f.codigo) {
            <label class="check">
              <input type="checkbox" [checked]="form.funcionalidades.includes(f.codigo)" (change)="alternar(f.codigo)" />
              <span><b>{{ f.nombre }}</b> @if (f.descripcion) { <span class="muted">— {{ f.descripcion }}</span> }</span>
            </label>
          }
        </fieldset>

        <div class="form-group" style="margin-top: 1rem;">
          <label>Descripción</label>
          <input type="text" [(ngModel)]="form.descripcion" name="descripcion" />
        </div>
        @if (error()) {
          <p class="error-text">{{ error() }}</p>
        }
        <div class="inline-form-actions">
          @if (editandoId()) {
            <button type="button" class="btn-secondary" (click)="cancelar()">Cancelar</button>
          }
          <button type="submit" class="btn-primary" [disabled]="guardando()">Guardar</button>
        </div>
      </form>
    </div>

    <div class="card table-wrap">
      <table class="data-table">
        <thead>
          <tr>
            <th>Plan</th>
            <th class="num">Precio</th>
            <th class="num">Duración</th>
            <th class="num">Sucursales</th>
            <th class="num">Usuarios</th>
            <th class="num">Productos</th>
            <th>Funcionalidades</th>
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
              <td class="num">{{ p.duracion_dias ? p.duracion_dias + ' días' : '—' }}</td>
              <td class="num">{{ p.max_sucursales ?? '∞' }}</td>
              <td class="num">{{ p.max_usuarios ?? '∞' }}</td>
              <td class="num">{{ p.max_productos ?? '∞' }}</td>
              <td>
                @for (c of p.funcionalidades; track c) {
                  <span class="badge badge-muted chip">{{ nombreFuncionalidad(c) }}</span>
                } @empty { <span class="muted">Ninguna</span> }
              </td>
              <td>
                <span class="badge" [class.badge-success]="p.activo" [class.badge-muted]="!p.activo">
                  {{ p.activo ? 'Activo' : 'Inactivo' }}
                </span>
              </td>
              <td class="acciones">
                <button class="btn-secondary" (click)="editar(p)">Editar</button>
                @if (p.activo) {
                  <button class="btn-secondary" (click)="desactivar(p)">Desactivar</button>
                } @else {
                  <button class="btn-secondary" (click)="reactivar(p)">Reactivar</button>
                }
                <button class="btn-danger" (click)="eliminar(p)">Eliminar</button>
              </td>
            </tr>
          } @empty {
            <tr><td colspan="9" class="muted">Todavía no hay planes.</td></tr>
          }
        </tbody>
      </table>
    </div>
  `,
  styles: `
    .form-title { font-size: 1rem; margin-bottom: 1rem; }
    .muted { color: var(--text-muted); font-size: 0.8rem; font-weight: 400; }
    .num { text-align: right; font-variant-numeric: tabular-nums; white-space: nowrap; }
    .acciones { display: flex; gap: 0.5rem; flex-wrap: wrap; }
    .table-wrap { overflow-x: auto; }
    .funcionalidades { border: 1px solid var(--border-color); border-radius: 8px; padding: 0.75rem 1rem; margin: 1rem 0 0; }
    .funcionalidades legend { font-size: 0.875rem; padding: 0 0.35rem; }
    .check { display: flex; align-items: flex-start; gap: 0.5rem; margin: 0.4rem 0; font-size: 0.875rem; }
    .chip { margin: 0 0.25rem 0.25rem 0; display: inline-block; }
    .error-text { color: var(--danger, #e5484d); font-size: 0.875rem; margin: 0.75rem 0 0; }
  `,
})
export class PlanesAdmin implements OnInit {
  private service = inject(EmpresasService);

  planes = signal<Plan[]>([]);
  funcionalidades = signal<Funcionalidad[]>([]);
  guardando = signal(false);
  editandoId = signal<number | null>(null);
  error = signal<string | null>(null);
  toast = signal<string | null>(null);
  toastIsError = signal(false);

  form: PlanCreate = this.vacio();

  ngOnInit() {
    this.cargar();
    this.service.listarFuncionalidades().subscribe((f) => this.funcionalidades.set(f));
  }

  private vacio(): PlanCreate {
    return {
      nombre: '', descripcion: '', precio_mensual: 0, duracion_dias: 30,
      max_sucursales: null, max_usuarios: null, max_productos: null, funcionalidades: [],
    };
  }

  nombreFuncionalidad(codigo: string): string {
    return this.funcionalidades().find((f) => f.codigo === codigo)?.nombre ?? codigo;
  }

  alternar(codigo: string) {
    const actuales = this.form.funcionalidades;
    this.form.funcionalidades = actuales.includes(codigo)
      ? actuales.filter((c) => c !== codigo)
      : [...actuales, codigo];
  }

  cargar() {
    this.service.listarTodosLosPlanes().subscribe((data) => this.planes.set(data));
  }

  /** Un input numérico vacío llega como '' o null: se manda null (= ilimitado / sin vencimiento). */
  private payload(): PlanCreate {
    const numero = (v: unknown) => (v === '' || v === null || v === undefined ? null : Number(v));
    return {
      ...this.form,
      precio_mensual: Number(this.form.precio_mensual),
      duracion_dias: numero(this.form.duracion_dias),
      max_sucursales: numero(this.form.max_sucursales),
      max_usuarios: numero(this.form.max_usuarios),
      max_productos: numero(this.form.max_productos),
    };
  }

  guardar() {
    const datos = this.payload();
    // CU3 6a: el límite tiene que ser mayor que cero.
    if ([datos.duracion_dias, datos.max_sucursales, datos.max_usuarios, datos.max_productos].some((v) => v !== null && v <= 0)) {
      this.error.set('Ingrese un límite mayor que cero');
      return;
    }
    this.error.set(null);
    this.guardando.set(true);
    const id = this.editandoId();
    const req = id ? this.service.actualizarPlan(id, datos) : this.service.crearPlan(datos);
    req.subscribe({
      next: () => {
        this.guardando.set(false);
        this.mostrarToast(id ? 'Plan actualizado' : 'Plan creado');
        this.cancelar();
        this.cargar();
      },
      error: (err) => {
        this.guardando.set(false);
        // CU3 7a: el backend lista las empresas que superan el nuevo límite.
        this.error.set(typeof err.error?.detail === 'string' ? err.error.detail : 'No se pudo guardar el plan');
      },
    });
  }

  editar(p: Plan) {
    this.editandoId.set(p.id);
    this.error.set(null);
    this.form = {
      nombre: p.nombre,
      descripcion: p.descripcion ?? '',
      precio_mensual: p.precio_mensual,
      duracion_dias: p.duracion_dias,
      max_sucursales: p.max_sucursales,
      max_usuarios: p.max_usuarios,
      max_productos: p.max_productos,
      funcionalidades: [...p.funcionalidades],
    };
    window.scrollTo({ top: 0, behavior: 'smooth' });
  }

  cancelar() {
    this.editandoId.set(null);
    this.error.set(null);
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

  /** CU3 2b: con empresas suscritas el backend no lo elimina y sugiere desactivarlo. */
  eliminar(p: Plan) {
    if (!confirm(`¿Eliminar el plan ${p.nombre}?`)) return;
    this.service.eliminarPlan(p.id).subscribe({
      next: () => {
        this.mostrarToast(`Plan ${p.nombre} eliminado`);
        this.cargar();
      },
      error: (err) => this.mostrarToast(err.error?.detail || 'No se pudo eliminar', true),
    });
  }

  private mostrarToast(msg: string, isError = false) {
    this.toast.set(msg);
    this.toastIsError.set(isError);
    setTimeout(() => this.toast.set(null), 6000);
  }
}
