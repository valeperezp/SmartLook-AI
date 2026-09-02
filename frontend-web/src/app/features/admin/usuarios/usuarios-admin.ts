import { Component, OnInit, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { UsuariosService } from '../../../core/services/usuarios.service';
import { Rol, Usuario } from '../../../core/models/usuario.model';

@Component({
  selector: 'app-usuarios-admin',
  standalone: true,
  imports: [CommonModule, FormsModule],
  template: `
    <div class="page-header">
      <h1>Usuarios y roles</h1>
      <p>Crear cuentas y asignar roles.</p>
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
            <label>Email</label>
            <input type="email" [(ngModel)]="nuevo.email" name="email" required />
          </div>
          <div class="form-group">
            <label>Contraseña</label>
            <input type="password" [(ngModel)]="nuevo.password" name="password" required minlength="6" />
          </div>
          <div class="form-group">
            <label>Rol</label>
            <select [(ngModel)]="nuevo.rol" name="rol">
              <option value="cliente">Cliente</option>
              <option value="administrador">Administrador</option>
            </select>
          </div>
        </div>
        <div class="inline-form-actions">
          <button type="submit" class="btn-primary" [disabled]="guardando()">Crear usuario</button>
        </div>
      </form>
    </div>

    <div class="card">
      <table class="data-table">
        <thead>
          <tr>
            <th>Nombre</th>
            <th>Email</th>
            <th>Rol</th>
            <th>Estado</th>
            <th>Acciones</th>
          </tr>
        </thead>
        <tbody>
          @for (u of usuarios(); track u.id) {
            <tr>
              <td>{{ u.nombre }}</td>
              <td>{{ u.email }}</td>
              <td>
                <select [ngModel]="u.rol" (ngModelChange)="cambiarRol(u, $event)">
                  <option value="cliente">Cliente</option>
                  <option value="administrador">Administrador</option>
                </select>
              </td>
              <td>
                <span class="badge" [class.badge-success]="u.activo" [class.badge-muted]="!u.activo">
                  {{ u.activo ? 'Activo' : 'Inactivo' }}
                </span>
              </td>
              <td>
                @if (u.activo) {
                  <button class="btn-danger" (click)="desactivar(u)">Desactivar</button>
                }
              </td>
            </tr>
          }
        </tbody>
      </table>
    </div>
  `,
})
export class UsuariosAdmin implements OnInit {
  private service = inject(UsuariosService);

  usuarios = signal<Usuario[]>([]);
  guardando = signal(false);
  toast = signal<string | null>(null);
  toastIsError = signal(false);

  nuevo = { nombre: '', email: '', password: '', rol: 'cliente' as Rol };

  ngOnInit() {
    this.cargar();
  }

  cargar() {
    this.service.listar().subscribe((data) => this.usuarios.set(data));
  }

  crear() {
    this.guardando.set(true);
    this.service.crear(this.nuevo).subscribe({
      next: () => {
        this.guardando.set(false);
        this.nuevo = { nombre: '', email: '', password: '', rol: 'cliente' };
        this.mostrarToast('Usuario creado con éxito');
        this.cargar();
      },
      error: (err) => {
        this.guardando.set(false);
        this.mostrarToast(err.error?.detail || 'Error al crear el usuario', true);
      },
    });
  }

  cambiarRol(usuario: Usuario, rol: Rol) {
    this.service.cambiarRol(usuario.id, rol).subscribe({
      next: () => {
        this.mostrarToast(`Rol de ${usuario.nombre} actualizado`);
        this.cargar();
      },
      error: () => this.mostrarToast('No se pudo cambiar el rol', true),
    });
  }

  desactivar(usuario: Usuario) {
    this.service.desactivar(usuario.id).subscribe({
      next: () => {
        this.mostrarToast(`${usuario.nombre} desactivado`);
        this.cargar();
      },
      error: () => this.mostrarToast('No se pudo desactivar el usuario', true),
    });
  }

  private mostrarToast(msg: string, isError = false) {
    this.toast.set(msg);
    this.toastIsError.set(isError);
    setTimeout(() => this.toast.set(null), 3500);
  }
}
