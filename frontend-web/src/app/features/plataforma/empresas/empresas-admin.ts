import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { EmpresasService } from '../../../core/services/empresas.service';
import {
  EmpresaCreada,
  EmpresaCreate,
  EmpresaDetalle,
  MetodoPago,
  Plan,
  Suscripcion,
} from '../../../core/models/empresa.model';
import { UsoBar } from '../shared/uso-bar';
import { estadoSuscripcion } from '../shared/estado-suscripcion';

/** CU2 — Gestionar empresas contratantes, y CU4 — Gestionar la suscripción de una empresa. */
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
      <button class="btn-primary" (click)="abrirAlta()">
        {{ mostrarAlta() ? 'Cerrar' : 'Nueva empresa' }}
      </button>
    </div>

    @if (toast()) {
      <div class="toast-notification" [class.toast-error]="toastIsError()">{{ toast() }}</div>
    }

    @if (creada(); as c) {
      <div class="card credenciales">
        <h3 class="form-title">Empresa {{ c.nombre }} registrada</h3>
        <p>Se enviaron las credenciales de acceso al administrador (envío simulado):</p>
        <p class="cred-linea">Correo: <b>{{ c.credenciales.email }}</b></p>
        @if (c.credenciales.password_temporal) {
          <p class="cred-linea">Contraseña temporal: <code>{{ c.credenciales.password_temporal }}</code></p>
        }
        <p class="cred-linea">Identificador para el login: <code>{{ c.slug }}</code></p>
        <div class="inline-form-actions">
          <button class="btn-secondary" (click)="creada.set(null)">Cerrar</button>
          @if (!c.suscripcion) {
            <button class="btn-primary" (click)="seleccionar(c); creada.set(null)">Asignarle un plan</button>
          }
        </div>
      </div>
    }

    @if (mostrarAlta()) {
      <div class="card" style="margin-bottom: 1.5rem;">
        <form (ngSubmit)="crear()" #f="ngForm">
          <h3 class="form-title">Datos de la empresa</h3>
          <div class="inline-form">
            <div class="form-group" [class.invalido]="enviado() && !nueva.nombre.trim()">
              <label>Razón social *</label>
              <input type="text" [(ngModel)]="nueva.nombre" name="nombre" />
            </div>
            <div class="form-group" [class.invalido]="enviado() && !nueva.nit.trim()">
              <label>NIT *</label>
              <input type="text" [(ngModel)]="nueva.nit" name="nit" />
            </div>
            <div class="form-group" [class.invalido]="enviado() && !nueva.email.trim()">
              <label>Correo *</label>
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

          <h3 class="form-title">Administrador de la empresa</h3>
          <div class="inline-form">
            <div class="form-group" [class.invalido]="enviado() && !nueva.administrador.nombre.trim()">
              <label>Nombre *</label>
              <input type="text" [(ngModel)]="nueva.administrador.nombre" name="admin_nombre" />
            </div>
            <div class="form-group" [class.invalido]="enviado() && !nueva.administrador.email.trim()">
              <label>Correo *</label>
              <input type="email" [(ngModel)]="nueva.administrador.email" name="admin_email" />
            </div>
            <div class="form-group">
              <label>Contraseña <span class="muted">(vacío = el sistema genera una temporal)</span></label>
              <input type="password" [(ngModel)]="nueva.administrador.password" name="admin_password" minlength="6" />
            </div>
          </div>

          <h3 class="form-title">Plan <span class="muted">(opcional: se puede asignar después)</span></h3>
          <div class="inline-form">
            <div class="form-group">
              <label>Plan</label>
              <select [(ngModel)]="nueva.plan_id" name="plan_id">
                <option [ngValue]="null">Asignar después</option>
                @for (p of planesActivos(); track p.id) {
                  <option [ngValue]="p.id">{{ p.nombre }} — Bs {{ p.precio_mensual | number: '1.0-2' }}</option>
                }
              </select>
            </div>
            @if (nueva.plan_id) {
              <div class="form-group">
                <label>Fecha de inicio</label>
                <input type="date" [(ngModel)]="nueva.fecha_inicio" name="fecha_inicio" />
              </div>
            }
          </div>
          @if (enviado() && faltantes().length) {
            <p class="error-text">Complete los campos obligatorios: {{ faltantes().join(', ') }}</p>
          }
          <div class="inline-form-actions">
            <button type="submit" class="btn-primary" [disabled]="guardando()">Guardar</button>
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
              @if (e.nit) { <span class="muted"> · NIT {{ e.nit }}</span> }
            </div>
            <div class="badges">
              @if (!e.activa) {
                <span class="badge badge-danger">Suspendida</span>
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
            <button class="btn-secondary" (click)="seleccionar(e)">Editar</button>
            <button class="btn-secondary" (click)="seleccionar(e, true)">Suscripción</button>
          </footer>
        </article>
      } @empty {
        <p class="muted">Todavía no hay empresas.</p>
      }
    </div>

    @if (seleccionada(); as e) {
      <div class="card detalle" id="detalle-empresa">
        <header class="detalle-head">
          <h2>{{ e.nombre }} <span class="badge" [ngClass]="e.activa ? 'badge-success' : 'badge-danger'">{{ e.activa ? 'Activa' : 'Suspendida' }}</span></h2>
          <button class="btn-secondary" (click)="seleccionada.set(null)">Cerrar</button>
        </header>

        <section>
          <h3 class="form-title">Datos</h3>
          <form (ngSubmit)="guardarDatos(e)">
            <div class="inline-form">
              <div class="form-group">
                <label>Razón social</label>
                <input type="text" [(ngModel)]="edicion.nombre" name="ed_nombre" required />
              </div>
              <div class="form-group">
                <label>NIT</label>
                <input type="text" [(ngModel)]="edicion.nit" name="ed_nit" />
              </div>
              <div class="form-group">
                <label>Correo</label>
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
                <button type="button" class="btn-danger" (click)="suspender(e)">Suspender</button>
              } @else {
                <button type="button" class="btn-secondary" (click)="reactivar(e)">Reactivar</button>
              }
              <button type="submit" class="btn-primary">Guardar</button>
            </div>
          </form>
        </section>

        <section id="suscripcion-empresa">
          <h3 class="form-title">Suscripción</h3>
          @if (e.suscripcion; as s) {
            <div class="resumen-suscripcion">
              <div><span class="muted">Plan actual</span><b>{{ s.plan.nombre }}</b></div>
              <div><span class="muted">Inicio</span><b>{{ s.fecha_inicio | date: 'dd/MM/yyyy' }}</b></div>
              <div><span class="muted">Vencimiento</span><b>{{ s.fecha_fin ? (s.fecha_fin | date: 'dd/MM/yyyy') : 'Sin vencimiento' }}</b></div>
              <div><span class="muted">Estado</span><span class="badge" [ngClass]="claseEstado(s.estado_mostrado)">{{ s.estado_mostrado }}</span></div>
            </div>
          } @else {
            <p class="muted">La empresa todavía no tiene plan: sus usuarios no pueden iniciar sesión.</p>
          }

          <h4 class="historial-title">Asignar plan</h4>
          <div class="inline-form">
            <div class="form-group">
              <label>Plan</label>
              <select [(ngModel)]="asignacion.plan_id" name="cambio_plan">
                @for (p of planesActivos(); track p.id) {
                  <option [ngValue]="p.id">
                    {{ p.nombre }} — {{ p.max_sucursales ?? 'sin límite de' }} sucursales · {{ p.duracion_dias ? p.duracion_dias + ' días' : 'sin vencimiento' }}
                  </option>
                }
              </select>
            </div>
            <div class="form-group">
              <label>Fecha de inicio</label>
              <input type="date" [(ngModel)]="asignacion.fecha_inicio" name="cambio_inicio" />
            </div>
            <div class="form-group">
              <label>Vence el <span class="muted">(calculado)</span></label>
              <input type="text" [value]="vencimientoCalculado()" disabled />
            </div>
            <div class="form-group">
              <label>Pago simulado</label>
              <select [(ngModel)]="asignacion.metodo" name="metodo">
                <option value="transferencia">Transferencia</option>
                <option value="efectivo">Efectivo</option>
                <option value="tarjeta">Tarjeta</option>
                <option value="qr">QR</option>
              </select>
            </div>
          </div>
          <div class="inline-form-actions">
            @if (e.suscripcion?.estado === 'activa') {
              <button class="btn-secondary" (click)="cambiarEstado(e, 'suspendida')">Suspender suscripción</button>
            }
            @if (e.suscripcion?.estado === 'suspendida') {
              <button class="btn-secondary" (click)="cambiarEstado(e, 'activa')">Reactivar suscripción</button>
            }
            @if (e.suscripcion?.fecha_fin && e.suscripcion?.estado !== 'cancelada') {
              <button class="btn-secondary" (click)="renovar(e)">Renovar</button>
            }
            <button class="btn-primary" (click)="asignarPlan(e)">Asignar plan</button>
          </div>

          <h4 class="historial-title">Historial de suscripciones</h4>
          <div class="table-wrap">
            <table class="data-table">
              <thead>
                <tr><th>Plan</th><th>Estado</th><th>Inicio</th><th>Vencimiento</th><th>Pago simulado</th></tr>
              </thead>
              <tbody>
                @for (s of historial(); track s.id) {
                  <tr>
                    <td>{{ s.plan.nombre }}</td>
                    <td><span class="badge" [ngClass]="claseEstado(s.estado_mostrado)">{{ s.estado_mostrado }}</span></td>
                    <td>{{ s.fecha_inicio | date: 'dd/MM/yyyy' }}</td>
                    <td>{{ s.fecha_fin ? (s.fecha_fin | date: 'dd/MM/yyyy') : '—' }}</td>
                    <td>
                      @if (s.monto_pagado !== null && s.monto_pagado !== undefined) {
                        Bs {{ s.monto_pagado | number: '1.2-2' }} · {{ s.metodo_pago_simulado }}
                      } @else { — }
                    </td>
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
  enviado = signal(false);
  creada = signal<EmpresaCreada | null>(null);
  toast = signal<string | null>(null);
  toastIsError = signal(false);

  readonly hoy = new Date().toISOString().slice(0, 10);
  readonly estado = estadoSuscripcion;

  nueva: EmpresaCreate & { nit: string; email: string } = this.vacia();
  edicion = { nombre: '', nit: '', email: '', telefono: '', direccion: '', logo_url: '' };
  asignacion: { plan_id: number | null; fecha_inicio: string; metodo: MetodoPago } = {
    plan_id: null, fecha_inicio: this.hoy, metodo: 'transferencia',
  };

  ngOnInit() {
    this.cargar();
    this.service.listarTodosLosPlanes().subscribe((planes) => this.planes.set(planes));
  }

  private vacia() {
    return {
      nombre: '', nit: '', email: '', telefono: '', direccion: '', logo_url: '',
      plan_id: null as number | null, fecha_inicio: this.hoy,
      administrador: { nombre: '', email: '', password: '' },
    };
  }

  abrirAlta() {
    this.mostrarAlta.set(!this.mostrarAlta());
    this.enviado.set(false);
  }

  /** CU2 6c: campos obligatorios vacíos. */
  faltantes(): string[] {
    const n = this.nueva;
    return [
      !n.nombre.trim() && 'razón social', !n.nit.trim() && 'NIT', !n.email.trim() && 'correo',
      !n.administrador.nombre.trim() && 'nombre del administrador',
      !n.administrador.email.trim() && 'correo del administrador',
    ].filter((x): x is string => !!x);
  }

  vencimientoCalculado(): string {
    const plan = this.planes().find((p) => p.id === this.asignacion.plan_id);
    if (!plan) return '';
    if (!plan.duracion_dias) return 'Sin vencimiento';
    const inicio = new Date(`${this.asignacion.fecha_inicio || this.hoy}T12:00:00`);
    inicio.setDate(inicio.getDate() + plan.duracion_dias);
    return inicio.toLocaleDateString('es-BO');
  }

  claseEstado(estado: string): string {
    return { vigente: 'badge-success', vencida: 'badge-danger', suspendida: 'badge-warning', cancelada: 'badge-danger' }[estado]
      ?? 'badge-muted';
  }

  cargar() {
    this.service.listar().subscribe((data) => {
      this.empresas.set(data);
      const sel = this.seleccionada();
      if (sel) this.seleccionada.set(data.find((e) => e.id === sel.id) ?? null);
    });
  }

  crear() {
    this.enviado.set(true);
    if (this.faltantes().length) return;
    this.guardando.set(true);
    const n = this.nueva;
    const data: EmpresaCreate = {
      ...n,
      plan_id: n.plan_id || null,
      fecha_inicio: n.plan_id ? n.fecha_inicio || null : null,
      administrador: { ...n.administrador, password: n.administrador.password || null },
    };
    this.service.crear(data).subscribe({
      next: (e) => {
        this.guardando.set(false);
        this.mostrarAlta.set(false);
        this.enviado.set(false);
        this.nueva = this.vacia();
        this.creada.set(e);
        this.cargar();
      },
      error: (err) => {
        this.guardando.set(false);
        this.mostrarToast(this.mensaje(err, 'No se pudo crear la empresa'), true);
      },
    });
  }

  seleccionar(e: EmpresaDetalle, irASuscripcion = false) {
    this.seleccionada.set(e);
    this.edicion = {
      nombre: e.nombre, nit: e.nit ?? '', email: e.email ?? '', telefono: e.telefono ?? '', direccion: e.direccion ?? '',
      logo_url: e.logo_url ?? '',
    };
    this.asignacion = {
      plan_id: e.suscripcion?.plan_id ?? this.planesActivos()[0]?.id ?? null,
      fecha_inicio: this.hoy,
      metodo: 'transferencia',
    };
    this.service.historial(e.id).subscribe((h) => this.historial.set(h));
    setTimeout(() => document.getElementById(irASuscripcion ? 'suscripcion-empresa' : 'detalle-empresa')
      ?.scrollIntoView({ behavior: 'smooth' }));
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

  suspender(e: EmpresaDetalle) {
    if (!confirm(`¿Suspender a ${e.nombre}? Sus usuarios no podrán iniciar sesión.`)) return;
    this.service.suspender(e.id).subscribe({
      next: () => {
        this.mostrarToast(`${e.nombre} suspendida`);
        this.cargar();
      },
      error: (err) => this.mostrarToast(this.mensaje(err, 'No se pudo suspender'), true),
    });
  }

  reactivar(e: EmpresaDetalle) {
    this.service.reactivar(e.id).subscribe({
      next: () => {
        this.mostrarToast(`${e.nombre} reactivada`);
        this.cargar();
      },
      error: (err) => this.mostrarToast(this.mensaje(err, 'No se pudo reactivar'), true),
    });
  }

  private refrescarSuscripcion(e: EmpresaDetalle, mensaje: string) {
    this.mostrarToast(mensaje);
    this.cargar();
    this.service.historial(e.id).subscribe((h) => this.historial.set(h));
  }

  asignarPlan(e: EmpresaDetalle) {
    if (!this.asignacion.plan_id) return;
    this.service
      .asignarPlan(e.id, {
        plan_id: this.asignacion.plan_id,
        fecha_inicio: this.asignacion.fecha_inicio || null,
        metodo_pago_simulado: this.asignacion.metodo,
      })
      .subscribe({
        next: (det) => this.refrescarSuscripcion(e, `Plan ${det.suscripcion?.plan.nombre} asignado a ${e.nombre}`),
        error: (err) => this.mostrarToast(this.mensaje(err, 'No se pudo asignar el plan'), true),
      });
  }

  renovar(e: EmpresaDetalle) {
    this.service.renovar(e.id).subscribe({
      next: (det) => this.refrescarSuscripcion(
        e, `Suscripción renovada hasta el ${new Date(det.suscripcion!.fecha_fin + 'T12:00:00').toLocaleDateString('es-BO')}`),
      error: (err) => this.mostrarToast(this.mensaje(err, 'No se pudo renovar'), true),
    });
  }

  cambiarEstado(e: EmpresaDetalle, estado: 'activa' | 'suspendida' | 'cancelada') {
    this.service.cambiarEstado(e.id, estado).subscribe({
      next: () => this.refrescarSuscripcion(e, 'Suscripción actualizada'),
      error: (err) => this.mostrarToast(this.mensaje(err, 'No se pudo cambiar el estado'), true),
    });
  }

  /** FastAPI devuelve `detail` como texto, o como lista cuando falla la validación. */
  private mensaje(err: any, porDefecto: string): string {
    const detail = err?.error?.detail;
    if (typeof detail === 'string') return detail;
    if (Array.isArray(detail) && detail[0]?.msg) return `Revise los datos: ${detail[0].msg}`;
    return porDefecto;
  }

  private mostrarToast(msg: string, isError = false) {
    this.toast.set(msg);
    this.toastIsError.set(isError);
    setTimeout(() => this.toast.set(null), 5000);
  }
}
