import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { EmpresasService } from '../../../core/services/empresas.service';
import { EmpresaCreate, EmpresaDetalle, Plan, Suscripcion } from '../../../core/models/empresa.model';
import { UsoBar } from '../shared/uso-bar';
import { estadoSuscripcion } from '../shared/estado-suscripcion';

/** CU2 — Gestionar empresas contratantes, y CU4 desde el lado del superadmin. */
@Component({
  selector: 'app-empresas-admin',
  standalone: true,
  imports: [CommonModule, FormsModule, UsoBar],
  template: `
    <div class="page-header header-row">
      <div>
        <h1>Empresas contratantes</h1>
        <p>Cada empresa tiene sus propios usuarios, sucursales y catálogo, según su plan.</p>
      </div>
      <button class="btn-primary" (click)="mostrarAlta.set(!mostrarAlta())">
        {{ mostrarAlta() ? 'Cerrar' : 'Nueva empresa' }}
      </button>
    </div>

    @if (toast()) {
      <div class="toast-notification" [class.toast-error]="toastIsError()">{{ toast() }}</div>
    }

    @if (mostrarAlta()) {
      <div class="card" style="margin-bottom: 1.5rem;">
        <form (ngSubmit)="crear()">
          <h3 class="form-title">Datos de la empresa</h3>
          <div class="inline-form">
            <div class="form-group">
              <label>Nombre</label>
              <input type="text" [(ngModel)]="nueva.nombre" name="nombre" required (input)="sugerirSlug()" />
            </div>
            <div class="form-group">
              <label>Identificador para el login</label>
              <input type="text" [(ngModel)]="nueva.slug" name="slug" required pattern="[a-z0-9]+(-[a-z0-9]+)*" />
            </div>
            <div class="form-group">
              <label>NIT</label>
              <input type="text" [(ngModel)]="nueva.nit" name="nit" />
            </div>
            <div class="form-group">
              <label>Email</label>
              <input type="email" [(ngModel)]="nueva.email" name="email" />
            </div>
            <div class="form-group">
              <label>Teléfono</label>
              <input type="text" [(ngModel)]="nueva.telefono" name="telefono" />
            </div>
            <div class="form-group">
              <label>Dirección</label>
              <input type="text" [(ngModel)]="nueva.direccion" name="direccion" />
            </div>
            <div class="form-group">
              <label>Logo (URL de imagen) <span class="muted">para los reportes</span></label>
              <input type="url" [(ngModel)]="nueva.logo_url" name="logo_url" placeholder="https://…/logo.png" />
            </div>
          </div>

          <h3 class="form-title">Plan contratado</h3>
          <div class="inline-form">
            <div class="form-group">
              <label>Plan</label>
              <select [(ngModel)]="nueva.plan_id" name="plan_id" required>
                @for (p of planesActivos(); track p.id) {
                  <option [ngValue]="p.id">{{ p.nombre }} — Bs {{ p.precio_mensual | number: '1.0-2' }}/mes</option>
                }
              </select>
            </div>
            <div class="form-group">
              <label>Vence el <span class="muted">(vacío = sin vencimiento)</span></label>
              <input type="date" [(ngModel)]="nueva.fecha_fin" name="fecha_fin" [min]="hoy" />
            </div>
          </div>

          <h3 class="form-title">Primer administrador</h3>
          <div class="inline-form">
            <div class="form-group">
              <label>Nombre</label>
              <input type="text" [(ngModel)]="nueva.administrador.nombre" name="admin_nombre" required />
            </div>
            <div class="form-group">
              <label>Email</label>
              <input type="email" [(ngModel)]="nueva.administrador.email" name="admin_email" required />
            </div>
            <div class="form-group">
              <label>Contraseña inicial</label>
              <input type="password" [(ngModel)]="nueva.administrador.password" name="admin_password" required minlength="6" />
            </div>
          </div>
          <div class="inline-form-actions">
            <button type="submit" class="btn-primary" [disabled]="guardando()">Crear empresa</button>
          </div>
        </form>
      </div>
    }

    <div class="empresas-grid">
      @for (e of empresas(); track e.id) {
        <article class="card empresa" [class.inactiva]="!e.activa" [class.seleccionada]="seleccionada()?.id === e.id">
          <header class="empresa-head">
            <div>
              <h3>{{ e.nombre }}</h3>
              <code class="slug">{{ e.slug }}</code>
            </div>
            <div class="badges">
              @if (!e.activa) {
                <span class="badge badge-muted">Dada de baja</span>
              }
              <span class="badge" [ngClass]="estado(e).clase">{{ estado(e).texto }}</span>
            </div>
          </header>

          <p class="plan-linea">
            @if (e.suscripcion) {
              Plan <b>{{ e.suscripcion.plan.nombre }}</b>
              @if (e.suscripcion.fecha_fin) { · vence {{ e.suscripcion.fecha_fin | date: 'dd/MM/yyyy' }} }
              @else { · sin vencimiento }
            } @else {
              Sin plan asignado
            }
          </p>

          <div class="usos">
            <app-uso-bar label="Sucursales" [valor]="e.uso.sucursales" />
            <app-uso-bar label="Usuarios" [valor]="e.uso.usuarios" />
            <app-uso-bar label="Productos" [valor]="e.uso.productos" />
          </div>

          <footer class="empresa-actions">
            <button class="btn-secondary" (click)="seleccionar(e)">Gestionar</button>
          </footer>
        </article>
      } @empty {
        <p class="muted">Todavía no hay empresas.</p>
      }
    </div>

    @if (seleccionada(); as e) {
      <div class="card detalle">
        <header class="detalle-head">
          <h2>{{ e.nombre }}</h2>
          <button class="btn-secondary" (click)="seleccionada.set(null)">Cerrar</button>
        </header>

        <section>
          <h3 class="form-title">Datos</h3>
          <form (ngSubmit)="guardarDatos(e)">
            <div class="inline-form">
              <div class="form-group">
                <label>Nombre</label>
                <input type="text" [(ngModel)]="edicion.nombre" name="ed_nombre" required />
              </div>
              <div class="form-group">
                <label>NIT</label>
                <input type="text" [(ngModel)]="edicion.nit" name="ed_nit" />
              </div>
              <div class="form-group">
                <label>Email</label>
                <input type="email" [(ngModel)]="edicion.email" name="ed_email" />
              </div>
              <div class="form-group">
                <label>Teléfono</label>
                <input type="text" [(ngModel)]="edicion.telefono" name="ed_tel" />
              </div>
              <div class="form-group">
                <label>Dirección</label>
                <input type="text" [(ngModel)]="edicion.direccion" name="ed_dir" />
              </div>
              <div class="form-group">
                <label>Logo (URL de imagen)</label>
                <input type="url" [(ngModel)]="edicion.logo_url" name="ed_logo" placeholder="https://…/logo.png" />
              </div>
            </div>
            <div class="inline-form-actions">
              @if (e.activa) {
                <button type="button" class="btn-danger" (click)="desactivar(e)">Dar de baja</button>
              } @else {
                <button type="button" class="btn-secondary" (click)="reactivar(e)">Reactivar empresa</button>
              }
              <button type="submit" class="btn-primary">Guardar datos</button>
            </div>
          </form>
        </section>

        <section>
          <h3 class="form-title">Suscripción</h3>
          <div class="inline-form">
            <div class="form-group">
              <label>Cambiar a plan</label>
              <select [(ngModel)]="cambioPlanId" name="cambio_plan">
                @for (p of planesActivos(); track p.id) {
                  <option [ngValue]="p.id">{{ p.nombre }}</option>
                }
              </select>
            </div>
            <div class="form-group">
              <label>Vence el</label>
              <input type="date" [(ngModel)]="cambioFechaFin" name="cambio_fin" [min]="hoy" />
            </div>
          </div>
          <div class="inline-form-actions">
            @if (e.suscripcion?.estado === 'activa') {
              <button class="btn-secondary" (click)="cambiarEstado(e, 'suspendida')">Suspender</button>
            }
            @if (e.suscripcion?.estado === 'suspendida') {
              <button class="btn-secondary" (click)="cambiarEstado(e, 'activa')">Reactivar suscripción</button>
            }
            @if (e.suscripcion && e.suscripcion.estado !== 'cancelada') {
              <button class="btn-danger" (click)="cambiarEstado(e, 'cancelada')">Cancelar suscripción</button>
            }
            <button class="btn-primary" (click)="asignarPlan(e)">Asignar plan</button>
          </div>

          <h4 class="historial-title">Historial</h4>
          <div class="table-wrap">
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
        </section>
      </div>
    }
  `,
  styleUrl: './empresas-admin.scss',
})
export class EmpresasAdmin implements OnInit {
  private service = inject(EmpresasService);

  empresas = signal<EmpresaDetalle[]>([]);
  planes = signal<Plan[]>([]);
  planesActivos = computed(() => this.planes().filter((p) => p.activo));
  seleccionada = signal<EmpresaDetalle | null>(null);
  historial = signal<Suscripcion[]>([]);
  mostrarAlta = signal(false);
  guardando = signal(false);
  toast = signal<string | null>(null);
  toastIsError = signal(false);

  readonly hoy = new Date().toISOString().slice(0, 10);
  readonly estado = estadoSuscripcion;

  nueva: EmpresaCreate = this.vacia();
  edicion = { nombre: '', nit: '', email: '', telefono: '', direccion: '', logo_url: '' };
  cambioPlanId: number | null = null;
  cambioFechaFin: string | null = null;

  ngOnInit() {
    this.cargar();
    this.service.listarTodosLosPlanes().subscribe((planes) => {
      this.planes.set(planes);
      this.nueva.plan_id = this.planesActivos()[0]?.id ?? 0;
    });
  }

  private vacia(): EmpresaCreate {
    return {
      nombre: '', slug: '', nit: '', email: '', telefono: '', direccion: '', logo_url: '',
      plan_id: this.planesActivos?.()[0]?.id ?? 0,
      fecha_fin: null,
      administrador: { nombre: '', email: '', password: '' },
    };
  }

  cargar() {
    this.service.listar().subscribe((data) => {
      this.empresas.set(data);
      const sel = this.seleccionada();
      if (sel) this.seleccionada.set(data.find((e) => e.id === sel.id) ?? null);
    });
  }

  /** "Moda Retro SRL" → "moda-retro-srl", mientras no lo hayan escrito a mano. */
  sugerirSlug() {
    this.nueva.slug = this.nueva.nombre
      .toLowerCase()
      .normalize('NFD')
      .replace(/[̀-ͯ]/g, '')
      .replace(/[^a-z0-9]+/g, '-')
      .replace(/^-+|-+$/g, '');
  }

  crear() {
    this.guardando.set(true);
    this.service.crear({ ...this.nueva, fecha_fin: this.nueva.fecha_fin || null }).subscribe({
      next: (e) => {
        this.guardando.set(false);
        this.mostrarAlta.set(false);
        this.nueva = this.vacia();
        this.mostrarToast(`${e.nombre} creada. Su administrador ya puede iniciar sesión.`);
        this.cargar();
      },
      error: (err) => {
        this.guardando.set(false);
        this.mostrarToast(this.mensaje(err, 'No se pudo crear la empresa'), true);
      },
    });
  }

  seleccionar(e: EmpresaDetalle) {
    this.seleccionada.set(e);
    this.edicion = {
      nombre: e.nombre, nit: e.nit ?? '', email: e.email ?? '', telefono: e.telefono ?? '', direccion: e.direccion ?? '',
      logo_url: e.logo_url ?? '',
    };
    this.cambioPlanId = e.suscripcion?.plan_id ?? this.planesActivos()[0]?.id ?? null;
    this.cambioFechaFin = e.suscripcion?.fecha_fin ?? null;
    this.service.historial(e.id).subscribe((h) => this.historial.set(h));
  }

  guardarDatos(e: EmpresaDetalle) {
    this.service.actualizar(e.id, this.edicion).subscribe({
      next: () => {
        this.mostrarToast('Datos guardados');
        this.cargar();
      },
      error: (err) => this.mostrarToast(this.mensaje(err, 'No se pudieron guardar los datos'), true),
    });
  }

  desactivar(e: EmpresaDetalle) {
    if (!confirm(`¿Dar de baja a ${e.nombre}? Sus usuarios no podrán iniciar sesión.`)) return;
    this.service.desactivar(e.id).subscribe({
      next: () => {
        this.mostrarToast(`${e.nombre} dada de baja`);
        this.cargar();
      },
      error: (err) => this.mostrarToast(this.mensaje(err, 'No se pudo dar de baja'), true),
    });
  }

  reactivar(e: EmpresaDetalle) {
    this.service.actualizar(e.id, { activa: true }).subscribe({
      next: () => {
        this.mostrarToast(`${e.nombre} reactivada`);
        this.cargar();
      },
      error: (err) => this.mostrarToast(this.mensaje(err, 'No se pudo reactivar'), true),
    });
  }

  asignarPlan(e: EmpresaDetalle) {
    if (!this.cambioPlanId) return;
    this.service.asignarPlan(e.id, this.cambioPlanId, this.cambioFechaFin || null).subscribe({
      next: (det) => {
        this.mostrarToast(`Plan ${det.suscripcion?.plan.nombre} asignado a ${e.nombre}`);
        this.cargar();
        this.service.historial(e.id).subscribe((h) => this.historial.set(h));
      },
      error: (err) => this.mostrarToast(this.mensaje(err, 'No se pudo asignar el plan'), true),
    });
  }

  cambiarEstado(e: EmpresaDetalle, estado: 'activa' | 'suspendida' | 'cancelada') {
    if (estado === 'cancelada' && !confirm(`¿Cancelar la suscripción de ${e.nombre}?`)) return;
    this.service.cambiarEstado(e.id, estado).subscribe({
      next: () => {
        this.mostrarToast('Suscripción actualizada');
        this.cargar();
        this.service.historial(e.id).subscribe((h) => this.historial.set(h));
      },
      error: (err) => this.mostrarToast(this.mensaje(err, 'No se pudo cambiar el estado'), true),
    });
  }

  /** FastAPI devuelve `detail` como texto, o como lista cuando falla la validación. */
  private mensaje(err: any, porDefecto: string): string {
    const detail = err?.error?.detail;
    if (typeof detail === 'string') return detail;
    if (Array.isArray(detail) && detail[0]?.msg) return `Revisá los datos: ${detail[0].msg}`;
    return porDefecto;
  }

  private mostrarToast(msg: string, isError = false) {
    this.toast.set(msg);
    this.toastIsError.set(isError);
    setTimeout(() => this.toast.set(null), 4000);
  }
}
