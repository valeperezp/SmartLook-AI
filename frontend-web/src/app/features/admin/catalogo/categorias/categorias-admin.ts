import { Component, OnInit, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { CatalogoService } from '../../../../core/services/catalogo.service';
import { Categoria } from '../../../../core/models/catalogo.model';

@Component({
  selector: 'app-categorias-admin',
  standalone: true,
  imports: [CommonModule, FormsModule],
  template: `
    <div class="page-header">
      <h1>Categorías</h1>
      <p>Lista maestra de categorías de prendas.</p>
    </div>

    @if (toast()) {
      <div class="toast-notification">{{ toast() }}</div>
    }

    <div class="card" style="margin-bottom: 1.5rem;">
      <form (ngSubmit)="crear()" class="form-row-inline">
        <div class="form-group">
          <label>Nombre</label>
          <input type="text" [(ngModel)]="nombre" name="nombre" placeholder="Ej. Camisetas" required />
        </div>
        <button type="submit" class="btn-primary" [disabled]="guardando()">Agregar</button>
      </form>
    </div>

    <div class="card">
      <table class="data-table">
        <thead><tr><th>Nombre</th><th>Estado</th><th>Acciones</th></tr></thead>
        <tbody>
          @for (c of items(); track c.id) {
            <tr>
              <td>{{ c.nombre }}</td>
              <td>
                <span class="badge" [class.badge-success]="c.activo" [class.badge-muted]="!c.activo">
                  {{ c.activo ? 'Activo' : 'Inactivo' }}
                </span>
              </td>
              <td>
                @if (c.activo) {
                  <button class="btn-danger" (click)="eliminar(c)">Desactivar</button>
                }
              </td>
            </tr>
          }
        </tbody>
      </table>
    </div>
  `,
  styles: [
    `.form-row-inline { display: flex; gap: 1rem; align-items: end; }
     .form-row-inline .form-group { flex: 1; max-width: 320px; }`,
  ],
})
export class CategoriasAdmin implements OnInit {
  private service = inject(CatalogoService);

  items = signal<Categoria[]>([]);
  nombre = '';
  guardando = signal(false);
  toast = signal<string | null>(null);

  ngOnInit() {
    this.cargar();
  }

  cargar() {
    this.service.listarCategorias().subscribe((data) => this.items.set(data));
  }

  crear() {
    this.guardando.set(true);
    this.service.crearCategoria(this.nombre).subscribe({
      next: () => {
        this.guardando.set(false);
        this.nombre = '';
        this.mostrarToast('Categoría creada');
        this.cargar();
      },
      error: () => this.guardando.set(false),
    });
  }

  eliminar(c: Categoria) {
    this.service.eliminarCategoria(c.id).subscribe(() => {
      this.mostrarToast(`${c.nombre} desactivada`);
      this.cargar();
    });
  }

  private mostrarToast(msg: string) {
    this.toast.set(msg);
    setTimeout(() => this.toast.set(null), 3000);
  }
}
