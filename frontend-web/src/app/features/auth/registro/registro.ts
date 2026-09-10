import { Component, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';
import { AuthService } from '../../../core/services/auth.service';
import { IconComponent } from '../../../core/components/icon/icon';

@Component({
  selector: 'app-registro',
  standalone: true,
  imports: [CommonModule, FormsModule, RouterLink, IconComponent],
  template: `
    <div class="auth-page">
      <div class="auth-showcase">
        <div class="showcase-content">
          <a routerLink="/" class="showcase-brand">
            <span class="logo-icon"><app-icon name="sparkles" [size]="18" /></span>
            <span>SmartLook<b>.AI</b></span>
          </a>
          <span class="eyebrow eyebrow-light">Nueva cuenta</span>
          <h2>Sumate a la moda inteligente</h2>
          <p>Creá tu cuenta y descubrí el catálogo, el vestidor virtual y recomendaciones hechas para vos.</p>
          <ul class="showcase-features">
            <li><span class="feature-icon"><app-icon name="focus" [size]="17" /></span> Vestidor virtual con AR</li>
            <li><span class="feature-icon"><app-icon name="sparkles" [size]="17" /></span> Recomendaciones con IA</li>
            <li><span class="feature-icon"><app-icon name="store" [size]="17" /></span> Reservá en tu sucursal</li>
          </ul>
        </div>
      </div>

      <div class="auth-form-panel">
        <div class="auth-card">
          <h1>Crear cuenta</h1>
          <p class="auth-subtitle">Registrate como cliente de SmartLook-AI</p>

          @if (error()) {
            <div class="auth-error">{{ error() }}</div>
          }

          <form (ngSubmit)="submit()" class="auth-form">
            <div class="form-group">
              <label>Nombre</label>
              <input type="text" [(ngModel)]="nombre" name="nombre" required autocomplete="name" />
            </div>
            <div class="form-group">
              <label>Email</label>
              <input type="email" [(ngModel)]="email" name="email" required autocomplete="email" />
            </div>
            <div class="form-group">
              <label>Contraseña</label>
              <input type="password" [(ngModel)]="password" name="password" required minlength="6" autocomplete="new-password" />
            </div>
            <button type="submit" class="btn-primary" [disabled]="loading()">
              @if (loading()) { Creando cuenta... } @else { Crear cuenta }
            </button>
          </form>

          <p class="auth-footer">¿Ya tenés cuenta? <a routerLink="/login">Iniciá sesión</a></p>
        </div>
      </div>
    </div>
  `,
  styleUrl: '../login/login.scss',
})
export class Registro {
  private auth = inject(AuthService);
  private router = inject(Router);

  nombre = '';
  email = '';
  password = '';
  loading = signal(false);
  error = signal<string | null>(null);

  submit() {
    this.loading.set(true);
    this.error.set(null);

    this.auth.registrar(this.nombre, this.email, this.password).subscribe({
      next: () => {
        this.auth.login(this.email, this.password).subscribe({
          next: () => {
            this.loading.set(false);
            this.router.navigate(['/']);
          },
          error: () => {
            this.loading.set(false);
            this.router.navigate(['/login']);
          },
        });
      },
      error: (err) => {
        this.loading.set(false);
        this.error.set(err.error?.detail || 'No se pudo crear la cuenta');
      },
    });
  }
}
