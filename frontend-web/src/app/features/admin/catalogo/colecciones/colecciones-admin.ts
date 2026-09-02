import { Component, OnInit, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { CatalogoService } from '../../../../core/services/catalogo.service';
import { Coleccion, Temporada } from '../../../../core/models/catalogo.model';

@Component({
  selector: 'app-colecciones-admin',
  standalone: true,
  imports: [CommonModule, FormsModule],
  template: `
    <div class="page-header">
      <h1>Colecciones</h1>
      <p>Lista maestra de colecciones, asociadas a una temporada.</p>
    </div>

    @if (toast()) {
      <div class="toast-notification">{{ toast() }}</div>
    }

    <div class="card" style="margin-bottom: 1.5rem;">
      <form (ngSubmit)="crear()" class="form-row-inline">
        <div class="form-group">
          <label>Nombre</label>
          <input type="text" [(ngModel)]="nombre" name="nombre" placeholder="Ej. Colección Básicos" required />
        </div>
        <div class="form-group">
          <label>Temporada</label>
          <select [(ngModel)]="temporadaId" name="temporadaId">
            <option [ngValue]="undefined">— Sin temporada —</option>
            @for (t of temporadas(); track t.id) {
              <option [ngValue]="t.id">{{ t.nombre }}</option>
            }
          </select>
        </div>
        <button type="submit" class="btn-primary" [disabled]="guardando()">Agregar</button>
      </form>
    </div>

    <div class="card">
      <table class="data-table">
        <thead><tr><th>Nombre</th><th>Temporada</th><th>Estado</th><th>Acciones</th></tr></thead>
        <tbody>
          @for (c of items(); track c.id) {
            <tr>
              <td>{{ c.nombre }}</td>
              <td>{{ c.temporada?.nombre || '—' }}</td>
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
     .form-row-inline .form-group { flex: 1; max-width: 300px; }`,
  ],
})
export class ColeccionesAdmin implements OnInit {
  private service = inject(CatalogoService);

  items = signal<Coleccion[]>([]);
  temporadas = signal<Temporada[]>([]);
  nombre = '';
  temporadaId?: number;
  guardando = signal(false);
  toast = signal<string | null>(null);

  ngOnInit() {
    this.cargar();
    this.service.listarTemporadas().subscribe((data) => this.temporadas.set(data));
  }

  cargar() {
    this.service.listarColecciones().subscribe((data) => this.items.set(data));
  }

  crear() {
    this.guardando.set(true);
    this.service.crearColeccion(this.nombre, this.temporadaId).subscribe({
      next: () => {
        this.guardando.set(false);
        this.nombre = '';
        this.temporadaId = undefined;
        this.mostrarToast('Colección creada');
        this.cargar();
      },
      error: () => this.guardando.set(false),
    });
  }

  eliminar(c: Coleccion) {
    this.service.eliminarColeccion(c.id).subscribe(() => {
      this.mostrarToast(`${c.nombre} desactivada`);
      this.cargar();
    });
  }

  private mostrarToast(msg: string) {
    this.toast.set(msg);
    setTimeout(() => this.toast.set(null), 3000);
  }
}
