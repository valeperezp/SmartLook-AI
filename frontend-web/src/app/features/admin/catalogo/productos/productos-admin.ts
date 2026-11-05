import { Component, OnInit, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { CatalogoService } from '../../../../core/services/catalogo.service';
import { ProveedoresService } from '../../../../core/services/proveedores.service';
import {
  Categoria,
  Coleccion,
  Color,
  Producto,
  Talla,
  Temporada,
  VarianteCreate,
} from '../../../../core/models/catalogo.model';
import { Proveedor } from '../../../../core/models/proveedor.model';

interface FormProducto {
  nombre: string;
  descripcion: string;
  precio: number | null;
  categoria_id?: number;
  temporada_id?: number;
  coleccion_id?: number;
  proveedor_id?: number;
}

/** CU7 — Productos de la empresa con sus variantes de talla, color y precio. */
@Component({
  selector: 'app-productos-admin',
  standalone: true,
  imports: [CommonModule, FormsModule],
  template: `
    <div class="page-header">
      <h1>Productos</h1>
      <p>Prendas del catálogo de tu empresa con sus variantes de talla, color y precio.</p>
    </div>

    @if (toast()) {
      <div class="toast-notification" [class.toast-error]="toastIsError()">{{ toast() }}</div>
    }

    <div class="card" style="margin-bottom: 1.5rem;">
      <h3 class="form-title">{{ editandoId() ? 'Editar producto' : 'Nuevo producto' }}</h3>
      <form (ngSubmit)="guardar()">
        <div class="form-row">
          <div class="form-group" [class.invalido]="enviado() && !form.nombre.trim()">
            <label>Nombre *</label>
            <input type="text" [(ngModel)]="form.nombre" name="nombre" />
          </div>
          <div class="form-group" [class.invalido]="enviado() && (form.precio === null || form.precio < 0)">
            <label>Precio *</label>
            <input type="number" [(ngModel)]="form.precio" name="precio" step="0.01" />
          </div>
        </div>

        <div class="form-group" style="margin-top: 1rem;">
          <label>Descripción</label>
          <textarea [(ngModel)]="form.descripcion" name="descripcion" rows="2"></textarea>
        </div>

        <div class="form-row" style="margin-top: 1rem;">
          <div class="form-group" [class.invalido]="enviado() && !form.categoria_id">
            <label>Categoría *</label>
            <select [(ngModel)]="form.categoria_id" name="categoria_id">
              <option [ngValue]="undefined">— Elegir —</option>
              @for (c of categorias(); track c.id) {
                <option [ngValue]="c.id">{{ c.nombre }}</option>
              }
            </select>
          </div>
          <div class="form-group">
            <label>Temporada</label>
            <select [(ngModel)]="form.temporada_id" name="temporada_id">
              <option [ngValue]="undefined">— Sin temporada —</option>
              @for (t of temporadas(); track t.id) {
                <option [ngValue]="t.id">{{ t.nombre }}</option>
              }
            </select>
          </div>
        </div>

        <div class="form-row" style="margin-top: 1rem;">
          <div class="form-group">
            <label>Colección</label>
            <select [(ngModel)]="form.coleccion_id" name="coleccion_id">
              <option [ngValue]="undefined">— Sin colección —</option>
              @for (c of colecciones(); track c.id) {
                <option [ngValue]="c.id">{{ c.nombre }}</option>
              }
            </select>
          </div>
          <div class="form-group">
            <label>Proveedor</label>
            <select [(ngModel)]="form.proveedor_id" name="proveedor_id">
              <option [ngValue]="undefined">— Sin proveedor —</option>
              @for (p of proveedores(); track p.id) {
                <option [ngValue]="p.id">{{ p.nombre }}</option>
              }
            </select>
          </div>
        </div>

        @if (!editandoId()) {
          <h4 class="sub">Variantes (talla y color)</h4>
          <div class="variante-alta">
            <select [(ngModel)]="nuevaTalla" name="nueva_talla">
              <option [ngValue]="null">Sin talla</option>
              @for (t of tallas(); track t.id) { <option [ngValue]="t.id">{{ t.nombre }}</option> }
            </select>
            <select [(ngModel)]="nuevoColor" name="nuevo_color">
              <option [ngValue]="null">Sin color</option>
              @for (c of colores(); track c.id) { <option [ngValue]="c.id">{{ c.nombre }}</option> }
            </select>
            <button type="button" class="btn-secondary" (click)="agregarVarianteAlForm()">Agregar variante</button>
          </div>
          @if (variantesForm.length) {
            <div class="chips">
              @for (v of variantesForm; track $index) {
                <span class="badge badge-muted chip">
                  {{ nombreTalla(v.talla_id) }} · {{ nombreColor(v.color_id) }}
                  <button type="button" (click)="quitarVarianteDelForm($index)" aria-label="Quitar">×</button>
                </span>
              }
            </div>
          }
        }

        @if (error()) { <p class="error-text">{{ error() }}</p> }
        <div class="inline-form-actions" style="margin-top: 1.25rem;">
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
            <th>Imagen</th>
            <th>Nombre</th>
            <th>Categoría</th>
            <th>Temporada</th>
            <th>Colección</th>
            <th>Precio</th>
            <th>Estado</th>
            <th>Acciones</th>
          </tr>
        </thead>
        <tbody>
          @for (p of items(); track p.id) {
            <tr>
              <td>
                <div style="display:flex; gap:0.5rem; align-items:center;">
                  @if (p.imagen_url) {
                    <img [src]="p.imagen_url" [alt]="p.nombre" style="width:36px; height:36px; object-fit:cover; border-radius:6px; border:1px solid var(--border-color);" />
                  } @else {
                    <span class="badge badge-muted">Sin imagen</span>
                  }
                  <label class="btn-secondary" style="cursor:pointer;">
                    @if (subiendoImagenId() === p.id) { Subiendo... } @else { {{ p.imagen_url ? 'Cambiar' : 'Subir' }} }
                    <input type="file" accept="image/*" style="display:none;" [disabled]="subiendoImagenId() === p.id"
                           (change)="onArchivoSeleccionado($event, p)" />
                  </label>
                </div>
              </td>
              <td>{{ p.nombre }}</td>
              <td>{{ p.categoria.nombre }}</td>
              <td>{{ p.temporada?.nombre || '—' }}</td>
              <td>{{ p.coleccion?.nombre || '—' }}</td>
              <td>Bs {{ p.precio | number:'1.2-2' }}</td>
              <td>
                <span class="badge" [class.badge-success]="p.activo" [class.badge-muted]="!p.activo">
                  {{ p.activo ? 'Activo' : 'Inactivo' }}
                </span>
              </td>
              <td class="acciones">
                <button class="btn-secondary" (click)="verVariantes(p)">Variantes</button>
                <button class="btn-secondary" (click)="editar(p)">Editar</button>
                @if (p.activo) {
                  <button class="btn-danger" (click)="desactivar(p)">Desactivar</button>
                } @else {
                  <button class="btn-secondary" (click)="reactivar(p)">Reactivar</button>
                }
              </td>
            </tr>
            @if (detalle()?.id === p.id) {
              <tr class="fila-variantes">
                <td colspan="8">
                  <div class="panel-variantes">
                    <h4 class="sub">Variantes de {{ p.nombre }}</h4>
                    <table class="data-table">
                      <thead><tr><th>Talla</th><th>Color</th><th>Precio</th><th>Estado</th><th></th></tr></thead>
                      <tbody>
                        @for (v of detalle()!.variantes ?? []; track v.id) {
                          <tr>
                            <td>{{ v.nombre_talla || '—' }}</td>
                            <td>{{ v.nombre_color || '—' }}</td>
                            <td>Bs {{ v.precio_efectivo | number:'1.2-2' }}</td>
                            <td><span class="badge" [class.badge-success]="v.activo" [class.badge-muted]="!v.activo">{{ v.activo ? 'Activa' : 'Inactiva' }}</span></td>
                            <td>@if (v.activo) { <button class="btn-secondary" (click)="desactivarVariante(p, v.id)">Desactivar</button> }</td>
                          </tr>
                        } @empty {
                          <tr><td colspan="5" class="muted">Sin variantes todavía.</td></tr>
                        }
                      </tbody>
                    </table>
                    <div class="variante-alta">
                      <select [(ngModel)]="nuevaTalla" name="det_talla">
                        <option [ngValue]="null">Sin talla</option>
                        @for (t of tallas(); track t.id) { <option [ngValue]="t.id">{{ t.nombre }}</option> }
                      </select>
                      <select [(ngModel)]="nuevoColor" name="det_color">
                        <option [ngValue]="null">Sin color</option>
                        @for (c of colores(); track c.id) { <option [ngValue]="c.id">{{ c.nombre }}</option> }
                      </select>
                      <input type="number" step="0.01" [(ngModel)]="nuevoPrecio" name="det_precio" placeholder="Precio (opcional)" />
                      <button class="btn-primary" (click)="agregarVariante(p)">Agregar variante</button>
                    </div>
                  </div>
                </td>
              </tr>
            }
          }
        </tbody>
      </table>
    </div>
  `,
  styles: `
    .form-title { font-size: 1rem; margin: 0 0 1rem; }
    .sub { font-size: 0.9rem; margin: 1.25rem 0 0.6rem; }
    .muted { color: var(--text-muted); font-size: 0.8rem; }
    .table-wrap { overflow-x: auto; }
    .acciones { display: flex; gap: 0.4rem; flex-wrap: wrap; }
    .variante-alta { display: flex; gap: 0.5rem; flex-wrap: wrap; align-items: center; margin-top: 0.75rem; }
    .variante-alta select, .variante-alta input { width: auto; min-width: 9rem; }
    .chips { display: flex; flex-wrap: wrap; gap: 0.4rem; margin-top: 0.75rem; }
    .chip { display: inline-flex; align-items: center; gap: 0.35rem; }
    .chip button { background: none; border: none; cursor: pointer; font-size: 1rem; line-height: 1; color: inherit; padding: 0; }
    .panel-variantes { padding: 0.5rem 0.25rem 1rem; }
    .fila-variantes > td { background: var(--bg-tertiary, rgba(127,127,127,0.06)); }
    .form-group.invalido input, .form-group.invalido select { border-color: var(--danger, #e5484d); }
    .error-text { color: var(--danger, #e5484d); font-size: 0.875rem; margin: 0.75rem 0 0; }
  `,
})
export class ProductosAdmin implements OnInit {
  private catalogoService = inject(CatalogoService);
  private proveedoresService = inject(ProveedoresService);

  items = signal<Producto[]>([]);
  categorias = signal<Categoria[]>([]);
  temporadas = signal<Temporada[]>([]);
  colecciones = signal<Coleccion[]>([]);
  proveedores = signal<Proveedor[]>([]);
  tallas = signal<Talla[]>([]);
  colores = signal<Color[]>([]);
  guardando = signal(false);
  enviado = signal(false);
  editandoId = signal<number | null>(null);
  detalle = signal<Producto | null>(null);
  error = signal<string | null>(null);
  toast = signal<string | null>(null);
  toastIsError = signal(false);
  subiendoImagenId = signal<number | null>(null);

  form: FormProducto = this.vacio();
  variantesForm: VarianteCreate[] = [];
  nuevaTalla: number | null = null;
  nuevoColor: number | null = null;
  nuevoPrecio: number | null = null;

  ngOnInit() {
    this.cargar();
    this.catalogoService.listarCategorias().subscribe((data) => this.categorias.set(data));
    this.catalogoService.listarTemporadas().subscribe((data) => this.temporadas.set(data));
    this.catalogoService.listarColecciones().subscribe((data) => this.colecciones.set(data));
    this.catalogoService.listarTallas().subscribe((data) => this.tallas.set(data.filter((t) => t.activo)));
    this.catalogoService.listarColores().subscribe((data) => this.colores.set(data.filter((c) => c.activo)));
    this.proveedoresService.listar().subscribe((data) => this.proveedores.set(data));
  }

  private vacio(): FormProducto {
    return { nombre: '', descripcion: '', precio: null };
  }

  cargar() {
    this.catalogoService.listarProductos(true).subscribe((data) => this.items.set(data));
  }

  nombreTalla(id: number | null) {
    return this.tallas().find((t) => t.id === id)?.nombre ?? 'Sin talla';
  }

  nombreColor(id: number | null) {
    return this.colores().find((c) => c.id === id)?.nombre ?? 'Sin color';
  }

  agregarVarianteAlForm() {
    // CU7 6b: la misma talla y color no se agrega dos veces.
    if (this.variantesForm.some((v) => v.talla_id === this.nuevaTalla && v.color_id === this.nuevoColor)) {
      this.error.set(`El producto ya tiene la variante ${this.nombreTalla(this.nuevaTalla)} · ${this.nombreColor(this.nuevoColor)}`);
      return;
    }
    this.error.set(null);
    this.variantesForm = [...this.variantesForm, { talla_id: this.nuevaTalla, color_id: this.nuevoColor }];
  }

  quitarVarianteDelForm(i: number) {
    this.variantesForm = this.variantesForm.filter((_, k) => k !== i);
  }

  guardar() {
    this.enviado.set(true);
    const f = this.form;
    // CU7 6a: datos incompletos o precio negativo.
    if (!f.nombre.trim() || f.precio === null || !f.categoria_id) {
      this.error.set('Complete los campos obligatorios');
      return;
    }
    if (f.precio < 0) {
      this.error.set('El precio no puede ser negativo');
      return;
    }
    this.error.set(null);
    this.guardando.set(true);
    const datos = {
      nombre: f.nombre,
      descripcion: f.descripcion || undefined,
      precio: f.precio,
      categoria_id: f.categoria_id,
      temporada_id: f.temporada_id,
      coleccion_id: f.coleccion_id,
      proveedor_id: f.proveedor_id,
    };
    const id = this.editandoId();
    const req = id
      ? this.catalogoService.actualizarProducto(id, datos)
      : this.catalogoService.crearProducto({ ...datos, variantes: this.variantesForm });
    req.subscribe({
      next: () => {
        this.guardando.set(false);
        this.mostrarToast(id ? 'Producto actualizado' : 'Producto creado');
        this.cancelar();
        this.cargar();
      },
      error: (err) => {
        this.guardando.set(false);
        // 403 = límite de productos del plan o suscripción vencida
        this.error.set(err.error?.detail || 'No se pudo guardar el producto');
      },
    });
  }

  editar(p: Producto) {
    this.editandoId.set(p.id);
    this.enviado.set(false);
    this.error.set(null);
    this.form = {
      nombre: p.nombre, descripcion: p.descripcion ?? '', precio: Number(p.precio),
      categoria_id: p.categoria_id, temporada_id: p.temporada_id ?? undefined,
      coleccion_id: p.coleccion_id ?? undefined, proveedor_id: p.proveedor_id ?? undefined,
    };
    window.scrollTo({ top: 0, behavior: 'smooth' });
  }

  cancelar() {
    this.editandoId.set(null);
    this.enviado.set(false);
    this.form = this.vacio();
    this.variantesForm = [];
  }

  verVariantes(p: Producto) {
    if (this.detalle()?.id === p.id) {
      this.detalle.set(null);
      return;
    }
    this.nuevaTalla = null;
    this.nuevoColor = null;
    this.nuevoPrecio = null;
    this.catalogoService.obtenerProducto(p.id).subscribe((d) => this.detalle.set(d));
  }

  agregarVariante(p: Producto) {
    this.catalogoService
      .agregarVariante(p.id, { talla_id: this.nuevaTalla, color_id: this.nuevoColor, precio: this.nuevoPrecio })
      .subscribe({
        next: () => {
          this.mostrarToast('Variante agregada');
          this.catalogoService.obtenerProducto(p.id).subscribe((d) => this.detalle.set(d));
        },
        error: (err) => this.mostrarToast(err.error?.detail || 'No se pudo agregar la variante', true),
      });
  }

  desactivarVariante(p: Producto, varianteId: number) {
    this.catalogoService.desactivarVariante(p.id, varianteId).subscribe({
      next: () => this.catalogoService.obtenerProducto(p.id).subscribe((d) => this.detalle.set(d)),
      error: (err) => this.mostrarToast(err.error?.detail || 'No se pudo desactivar la variante', true),
    });
  }

  desactivar(p: Producto) {
    this.catalogoService.eliminarProducto(p.id).subscribe({
      next: () => {
        this.mostrarToast(`${p.nombre} desactivado: ya no se muestra en el catálogo`);
        this.cargar();
      },
      error: (err) => this.mostrarToast(err.error?.detail || 'No se pudo desactivar', true),
    });
  }

  reactivar(p: Producto) {
    this.catalogoService.actualizarProducto(p.id, { activo: true }).subscribe({
      next: () => {
        this.mostrarToast(`${p.nombre} reactivado`);
        this.cargar();
      },
      error: (err) => this.mostrarToast(err.error?.detail || 'No se pudo reactivar', true),
    });
  }

  onArchivoSeleccionado(event: Event, p: Producto) {
    const input = event.target as HTMLInputElement;
    const archivo = input.files?.[0];
    if (!archivo) return;

    this.subiendoImagenId.set(p.id);
    this.catalogoService.subirImagenProducto(p.id, archivo).subscribe({
      next: () => {
        this.mostrarToast('Imagen subida');
        this.subiendoImagenId.set(null);
        input.value = '';
        this.cargar();
      },
      error: (err) => {
        this.mostrarToast(err.error?.detail || 'Error al subir la imagen', true);
        this.subiendoImagenId.set(null);
        input.value = '';
      },
    });
  }

  private mostrarToast(msg: string, isError = false) {
    this.toast.set(msg);
    this.toastIsError.set(isError);
    setTimeout(() => this.toast.set(null), 4000);
  }
}
