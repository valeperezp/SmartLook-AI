import { Component, OnInit, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { CatalogoService } from '../../../../core/services/catalogo.service';
import { ProveedoresService } from '../../../../core/services/proveedores.service';
import { Categoria, Coleccion, Producto, Temporada } from '../../../../core/models/catalogo.model';
import { Proveedor } from '../../../../core/models/proveedor.model';

@Component({
  selector: 'app-productos-admin',
  standalone: true,
  imports: [CommonModule, FormsModule],
  template: `
    <div class="page-header">
      <h1>Productos</h1>
      <p>Alta de prendas del catálogo.</p>
    </div>

    @if (toast()) {
      <div class="toast-notification">{{ toast() }}</div>
    }

    <div class="card" style="margin-bottom: 1.5rem;">
      <form (ngSubmit)="crear()">
        <div class="form-row">
          <div class="form-group">
            <label>Nombre *</label>
            <input type="text" [(ngModel)]="nuevo.nombre" name="nombre" required />
          </div>
          <div class="form-group">
            <label>Precio *</label>
            <input type="number" [(ngModel)]="nuevo.precio" name="precio" step="0.01" min="0" required />
          </div>
        </div>

        <div class="form-group" style="margin-top: 1rem;">
          <label>Descripción</label>
          <textarea [(ngModel)]="nuevo.descripcion" name="descripcion" rows="2"></textarea>
        </div>

        <div class="form-row" style="margin-top: 1rem;">
          <div class="form-group">
            <label>Categoría *</label>
            <select [(ngModel)]="nuevo.categoria_id" name="categoria_id" required>
              <option [ngValue]="undefined">— Elegir —</option>
              @for (c of categorias(); track c.id) {
                <option [ngValue]="c.id">{{ c.nombre }}</option>
              }
            </select>
          </div>
          <div class="form-group">
            <label>Temporada</label>
            <select [(ngModel)]="nuevo.temporada_id" name="temporada_id">
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
            <select [(ngModel)]="nuevo.coleccion_id" name="coleccion_id">
              <option [ngValue]="undefined">— Sin colección —</option>
              @for (c of colecciones(); track c.id) {
                <option [ngValue]="c.id">{{ c.nombre }}</option>
              }
            </select>
          </div>
          <div class="form-group">
            <label>Proveedor</label>
            <select [(ngModel)]="nuevo.proveedor_id" name="proveedor_id">
              <option [ngValue]="undefined">— Sin proveedor —</option>
              @for (p of proveedores(); track p.id) {
                <option [ngValue]="p.id">{{ p.nombre }}</option>
              }
            </select>
          </div>
        </div>

        <button type="submit" class="btn-primary" style="margin-top: 1.25rem;" [disabled]="guardando()">
          Crear producto
        </button>
      </form>
    </div>

    <div class="card">
      <table class="data-table">
        <thead>
          <tr>
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
              <td>{{ p.nombre }}</td>
              <td>{{ p.categoria.nombre }}</td>
              <td>{{ p.temporada?.nombre || '—' }}</td>
              <td>{{ p.coleccion?.nombre || '—' }}</td>
              <td>&#36;{{ p.precio | number:'1.2-2' }}</td>
              <td>
                <span class="badge" [class.badge-success]="p.activo" [class.badge-muted]="!p.activo">
                  {{ p.activo ? 'Activo' : 'Inactivo' }}
                </span>
              </td>
              <td>
                @if (p.activo) {
                  <button class="btn-danger" (click)="eliminar(p)">Desactivar</button>
                }
              </td>
            </tr>
          }
        </tbody>
      </table>
    </div>
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
  guardando = signal(false);
  toast = signal<string | null>(null);

  nuevo: {
    nombre: string;
    descripcion: string;
    precio: number | null;
    categoria_id?: number;
    temporada_id?: number;
    coleccion_id?: number;
    proveedor_id?: number;
  } = { nombre: '', descripcion: '', precio: null };

  ngOnInit() {
    this.cargar();
    this.catalogoService.listarCategorias().subscribe((data) => this.categorias.set(data));
    this.catalogoService.listarTemporadas().subscribe((data) => this.temporadas.set(data));
    this.catalogoService.listarColecciones().subscribe((data) => this.colecciones.set(data));
    this.proveedoresService.listar().subscribe((data) => this.proveedores.set(data));
  }

  cargar() {
    this.catalogoService.listarProductos(true).subscribe((data) => this.items.set(data));
  }

  crear() {
    if (!this.nuevo.categoria_id || this.nuevo.precio === null) return;

    this.guardando.set(true);
    this.catalogoService
      .crearProducto({
        nombre: this.nuevo.nombre,
        descripcion: this.nuevo.descripcion || undefined,
        precio: this.nuevo.precio,
        categoria_id: this.nuevo.categoria_id,
        temporada_id: this.nuevo.temporada_id,
        coleccion_id: this.nuevo.coleccion_id,
        proveedor_id: this.nuevo.proveedor_id,
      })
      .subscribe({
        next: () => {
          this.guardando.set(false);
          this.nuevo = { nombre: '', descripcion: '', precio: null };
          this.mostrarToast('Producto creado');
          this.cargar();
        },
        error: () => this.guardando.set(false),
      });
  }

  eliminar(p: Producto) {
    this.catalogoService.eliminarProducto(p.id).subscribe(() => {
      this.mostrarToast(`${p.nombre} desactivado`);
      this.cargar();
    });
  }

  private mostrarToast(msg: string) {
    this.toast.set(msg);
    setTimeout(() => this.toast.set(null), 3000);
  }
}
