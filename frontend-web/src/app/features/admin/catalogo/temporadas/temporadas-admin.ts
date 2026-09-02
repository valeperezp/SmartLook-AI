import { Component, OnInit, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { CatalogoService } from '../../../../core/services/catalogo.service';
import { Temporada } from '../../../../core/models/catalogo.model';

@Component({
  selector: 'app-temporadas-admin',
  standalone: true,
  imports: [CommonModule, FormsModule],
  template: `
    <div class="page-header">
      <h1>Temporadas</h1>
      <p>Lista maestra de temporadas comerciales.</p>
    </div>

    @if (toast()) {
      <div class="toast-notification">{{ toast() }}</div>
    }

    <div class="card" style="margin-bottom: 1.5rem;">
      <form (ngSubmit)="crear()" class="form-row-inline">
        <div class="form-group">
          <label>Nombre</label>
          <input type="text" [(ngModel)]="nombre" name="nombre" placeholder="Ej. Primavera-Verano 2026" required />
        </div>
        <button type="submit" class="btn-primary" [disabled]="guardando()">Agregar</button>
      </form>
    </div>

    <div class="card">
      <table class="data-table">
        <thead><tr><th>Nombre</th><th>Estado</th><th>Acciones</th></tr></thead>
        <tbody>
          @for (t of items(); track t.id) {
            <tr>
              <td>{{ t.nombre }}</td>
              <td>
                <span class="badge" [class.badge-success]="t.activo" [class.badge-muted]="!t.activo">
                  {{ t.activo ? 'Activo' : 'Inactivo' }}
                </span>
              </td>
              <td>
                @if (t.activo) {
                  <button class="btn-danger" (click)="eliminar(t)">Desactivar</button>
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
     .form-row-inline .form-group { flex: 1; max-width: 360px; }`,
  ],
})
export class TemporadasAdmin implements OnInit {
  private service = inject(CatalogoService);

  items = signal<Temporada[]>([]);
  nombre = '';
  guardando = signal(false);
  toast = signal<string | null>(null);

  ngOnInit() {
    this.cargar();
  }

  cargar() {
    this.service.listarTemporadas().subscribe((data) => this.items.set(data));
  }

  crear() {
    this.guardando.set(true);
    this.service.crearTemporada(this.nombre).subscribe({
      next: () => {
        this.guardando.set(false);
        this.nombre = '';
        this.mostrarToast('Temporada creada');
        this.cargar();
      },
      error: () => this.guardando.set(false),
    });
  }

  eliminar(t: Temporada) {
    this.service.eliminarTemporada(t.id).subscribe(() => {
      this.mostrarToast(`${t.nombre} desactivada`);
      this.cargar();
    });
  }

  private mostrarToast(msg: string) {
    this.toast.set(msg);
    setTimeout(() => this.toast.set(null), 3000);
  }
}
