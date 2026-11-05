import { Component, OnInit, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { HttpErrorResponse } from '@angular/common/http';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { AuthService } from '../../../core/services/auth.service';
import { EmpresasService } from '../../../core/services/empresas.service';
import { IconComponent } from '../../../core/components/icon/icon';

@Component({
  selector: 'app-login',
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
          <h2>Tu clóset digital te está esperando</h2>
          <p>Iniciá sesión para reservar prendas, ver tu historial y probarte outfits con realidad aumentada.</p>
          <ul class="showcase-features">
            <li><span class="feature-icon"><app-icon name="focus" [size]="17" /></span> Vestidor virtual con AR</li>
            <li><span class="feature-icon"><app-icon name="sparkles" [size]="17" /></span> Recomendaciones con IA</li>
            <li><span class="feature-icon"><app-icon name="store" [size]="17" /></span> Reservá en tu sucursal</li>
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
              <label>Empresa <span class="label-hint">(opcional)</span></label>
              <input
                type="text"
                [(ngModel)]="empresa"
                name="empresa"
                placeholder="ej: smartlook"
                autocomplete="organization"
                (blur)="buscarEmpresa()"
              />
              @if (empresaNombre()) {
                <small class="empresa-ok">Ingresando a <b>{{ empresaNombre() }}</b></small>
              } @else if (empresaNoExiste()) {
                <small class="empresa-error">No existe una empresa con ese identificador</small>
              }
            </div>
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
export class Login implements OnInit {
  private auth = inject(AuthService);
  private empresas = inject(EmpresasService);
  private router = inject(Router);
  private route = inject(ActivatedRoute);

  empresa = '';
  email = '';
  password = '';
  loading = signal(false);
  error = signal<string | null>(null);
  empresaNombre = signal<string | null>(null);
  empresaNoExiste = signal(false);

  ngOnInit() {
    // Permite compartir un link de login propio de cada empresa: /login?empresa=smartlook
    const slug = this.route.snapshot.queryParamMap.get('empresa');
    if (slug) {
      this.empresa = slug;
      this.buscarEmpresa();
    }
  }

  private slug(): string {
    return this.empresa.trim().toLowerCase();
  }

  buscarEmpresa() {
    this.empresaNombre.set(null);
    this.empresaNoExiste.set(false);
    const slug = this.slug();
    if (!slug) return;
    this.empresas.empresaPublica(slug).subscribe({
      next: (e) => {
        this.empresaNombre.set(e.nombre);
        this.auth.setEmpresaVisitada(e.slug);
      },
      error: () => this.empresaNoExiste.set(true),
    });
  }

  submit() {
    this.loading.set(true);
    this.error.set(null);

    this.auth.login(this.email, this.password, this.slug() || null).subscribe({
      next: () => {
        this.loading.set(false);
        this.router.navigate([this.auth.getHomeRoute()]);
      },
      error: (err: HttpErrorResponse) => {
        this.loading.set(false);
        // CU1: 401 "Credenciales inválidas", 403 usuario inactivo o empresa suspendida, 404 empresa inexistente.
        const detalle = [401, 403, 404].includes(err.status) && typeof err.error?.detail === 'string'
          ? err.error.detail : null;
        this.error.set(detalle || (err.status === 0 ? 'No se pudo conectar con el servidor' : 'Credenciales inválidas'));
      },
    });
  }
}
