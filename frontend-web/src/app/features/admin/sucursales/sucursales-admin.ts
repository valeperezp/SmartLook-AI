import { Component, OnInit, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { SucursalesService } from '../../../core/services/sucursales.service';
import { Sucursal } from '../../../core/models/sucursal.model';

@Component({
  selector: 'app-sucursales-admin',
  standalone: true,
  imports: [CommonModule, FormsModule],
  template: `
    <div class="page-header">
      <h1>Sucursales</h1>
      <p>Administrar las sucursales de la cadena.</p>
    </div>

    @if (toast()) {
      <div class="toast-notification" [class.toast-error]="toastIsError()">{{ toast() }}</div>
    }

    <div class="card" style="margin-bottom: 1.5rem;">
      <form (ngSubmit)="crear()">
        <div class="inline-form">
          <div class="form-group">
            <label>Nombre</label>
            <input type="text" [(ngModel)]="nuevo.nombre" name="nombre" required />
          </div>
          <div class="form-group">
            <label>Dirección</label>
            <input type="text" [(ngModel)]="nuevo.direccion" name="direccion" required />
          </div>
          <div class="form-group">
            <label>Ciudad</label>
            <input type="text" [(ngModel)]="nuevo.ciudad" name="ciudad" />
          </div>
          <div class="form-group">
            <label>Teléfono</label>
            <input type="text" [(ngModel)]="nuevo.telefono" name="telefono" />
          </div>
        </div>
        <div class="inline-form-actions">
          <button type="submit" class="btn-primary" [disabled]="guardando()">Crear sucursal</button>
        </div>
      </form>
    </div>

    <div class="card">
      <table class="data-table">
        <thead>
          <tr>
            <th>Nombre</th>
            <th>Dirección</th>
            <th>Ciudad</th>
            <th>Teléfono</th>
            <th>Estado</th>
            <th>Acciones</th>
          </tr>
        </thead>
        <tbody>
          @for (s of sucursales(); track s.id) {
            <tr>
              <td>{{ s.nombre }}</td>
              <td>{{ s.direccion }}</td>
              <td>{{ s.ciudad || '—' }}</td>
              <td>{{ s.telefono || '—' }}</td>
              <td>
                <span class="badge" [class.badge-success]="s.activa" [class.badge-muted]="!s.activa">
                  {{ s.activa ? 'Activa' : 'Inactiva' }}
                </span>
              </td>
              <td>
                @if (s.activa) {
                  <button class="btn-danger" (click)="eliminar(s)">Desactivar</button>
                }
              </td>
            </tr>
          }
        </tbody>
      </table>
    </div>
  `,
})
export class SucursalesAdmin implements OnInit {
  private service = inject(SucursalesService);

  sucursales = signal<Sucursal[]>([]);
  guardando = signal(false);
  toast = signal<string | null>(null);
  toastIsError = signal(false);

  nuevo = { nombre: '', direccion: '', ciudad: '', telefono: '' };

  ngOnInit() {
    this.cargar();
  }

  cargar() {
    this.service.listar().subscribe((data) => this.sucursales.set(data));
  }

  crear() {
    this.guardando.set(true);
    this.service.crear(this.nuevo).subscribe({
      next: () => {
        this.guardando.set(false);
        this.nuevo = { nombre: '', direccion: '', ciudad: '', telefono: '' };
        this.mostrarToast('Sucursal creada con éxito');
        this.cargar();
      },
      error: () => {
        this.guardando.set(false);
        this.mostrarToast('Error al crear la sucursal', true);
      },
    });
  }

  eliminar(s: Sucursal) {
    this.service.eliminar(s.id).subscribe({
      next: () => {
        this.mostrarToast(`${s.nombre} desactivada`);
        this.cargar();
      },
      error: () => this.mostrarToast('No se pudo desactivar', true),
    });
  }

  private mostrarToast(msg: string, isError = false) {
    this.toast.set(msg);
    this.toastIsError.set(isError);
    setTimeout(() => this.toast.set(null), 3500);
  }
}
