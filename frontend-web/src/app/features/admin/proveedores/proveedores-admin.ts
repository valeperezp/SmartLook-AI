import { Component, OnInit, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ProveedoresService } from '../../../core/services/proveedores.service';
import { Proveedor } from '../../../core/models/proveedor.model';

@Component({
  selector: 'app-proveedores-admin',
  standalone: true,
  imports: [CommonModule, FormsModule],
  template: `
    <div class="page-header">
      <h1>Proveedores</h1>
      <p>Administrar los proveedores de prendas.</p>
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
            <label>Contacto</label>
            <input type="text" [(ngModel)]="nuevo.contacto" name="contacto" />
          </div>
          <div class="form-group">
            <label>Teléfono</label>
            <input type="text" [(ngModel)]="nuevo.telefono" name="telefono" />
          </div>
          <div class="form-group">
            <label>Email</label>
            <input type="email" [(ngModel)]="nuevo.email" name="email" />
          </div>
        </div>
        <div class="inline-form-actions">
          <button type="submit" class="btn-primary" [disabled]="guardando()">Crear proveedor</button>
        </div>
      </form>
    </div>

    <div class="card">
      <table class="data-table">
        <thead>
          <tr>
            <th>Nombre</th>
            <th>Contacto</th>
            <th>Teléfono</th>
            <th>Email</th>
            <th>Estado</th>
            <th>Acciones</th>
          </tr>
        </thead>
        <tbody>
          @for (p of proveedores(); track p.id) {
            <tr>
              <td>{{ p.nombre }}</td>
              <td>{{ p.contacto || '—' }}</td>
              <td>{{ p.telefono || '—' }}</td>
              <td>{{ p.email || '—' }}</td>
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
export class ProveedoresAdmin implements OnInit {
  private service = inject(ProveedoresService);

  proveedores = signal<Proveedor[]>([]);
  guardando = signal(false);
  toast = signal<string | null>(null);
  toastIsError = signal(false);

  nuevo = { nombre: '', contacto: '', telefono: '', email: '' };

  ngOnInit() {
    this.cargar();
  }

  cargar() {
    this.service.listar().subscribe((data) => this.proveedores.set(data));
  }

  crear() {
    this.guardando.set(true);
    this.service.crear(this.nuevo).subscribe({
      next: () => {
        this.guardando.set(false);
        this.nuevo = { nombre: '', contacto: '', telefono: '', email: '' };
        this.mostrarToast('Proveedor creado con éxito');
        this.cargar();
      },
      error: () => {
        this.guardando.set(false);
        this.mostrarToast('Error al crear el proveedor', true);
      },
    });
  }

  eliminar(p: Proveedor) {
    this.service.eliminar(p.id).subscribe({
      next: () => {
        this.mostrarToast(`${p.nombre} desactivado`);
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
