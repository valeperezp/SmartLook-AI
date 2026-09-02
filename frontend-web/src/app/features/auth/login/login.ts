import { Component, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';
import { AuthService } from '../../../core/services/auth.service';

@Component({
  selector: 'app-login',
  standalone: true,
  imports: [CommonModule, FormsModule, RouterLink],
  template: `
    <div class="auth-page">
      <div class="auth-showcase">
        <div class="showcase-blob blob-1"></div>
        <div class="showcase-blob blob-2"></div>
        <div class="showcase-content">
          <a routerLink="/" class="showcase-brand">
            <span class="logo-icon">✨</span>
            <span>SmartLook<b>.AI</b></span>
          </a>
          <h2>Tu clóset digital te está esperando</h2>
          <p>Iniciá sesión para reservar prendas, ver tu historial y probarte outfits con realidad aumentada.</p>
          <ul class="showcase-features">
            <li><span class="feature-icon">🪞</span> Vestidor virtual con AR</li>
            <li><span class="feature-icon">🤖</span> Recomendaciones con IA</li>
            <li><span class="feature-icon">📍</span> Reservá en tu sucursal</li>
          </ul>
        </div>
      </div>

      <div class="auth-form-panel">
        <div class="auth-card">
          <h1>Iniciar sesión</h1>
          <p class="auth-subtitle">Entrá con tu cuenta de SmartLook-AI</p>

          @if (error()) {
            <div class="auth-error">{{ error() }}</div>
          }

          <form (ngSubmit)="submit()" class="auth-form">
            <div class="form-group">
              <label>Email</label>
              <input type="email" [(ngModel)]="email" name="email" required autocomplete="email" />
            </div>
            <div class="form-group">
              <label>Contraseña</label>
              <input type="password" [(ngModel)]="password" name="password" required autocomplete="current-password" />
            </div>
            <button type="submit" class="btn-primary" [disabled]="loading()">
              @if (loading()) { Entrando... } @else { Entrar }
            </button>
          </form>

          <p class="auth-footer">¿No tenés cuenta? <a routerLink="/registro">Registrate</a></p>
        </div>
      </div>
    </div>
  `,
  styleUrl: './login.scss',
})
export class Login {
  private auth = inject(AuthService);
  private router = inject(Router);

  email = '';
  password = '';
  loading = signal(false);
  error = signal<string | null>(null);

  submit() {
    this.loading.set(true);
    this.error.set(null);

    this.auth.login(this.email, this.password).subscribe({
      next: () => {
        this.loading.set(false);
        this.router.navigate([this.auth.isAdmin() ? '/admin' : '/']);
      },
      error: () => {
        this.loading.set(false);
        this.error.set('Email o contraseña incorrectos');
      },
    });
  }
}
