import { Component, OnInit, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { HttpClient } from '@angular/common/http';
import { RouterLink } from '@angular/router';
import { AuthService } from '../../../core/services/auth.service';
import { environment } from '../../../../environments/environment';
import { IconComponent, IconName } from '../../../core/components/icon/icon';

interface ModuloCard {
  ruta: string;
  icono: IconName;
  titulo: string;
  descripcion: string;
}

interface GrupoModulos {
  nombre: string;
  modulos: ModuloCard[];
}

@Component({
  selector: 'app-admin-dashboard',
  standalone: true,
  imports: [CommonModule, RouterLink, IconComponent],
  template: `
    <div class="dash-header">
      <h1>{{ saludo() }}, <span class="gradient-text">{{ nombre() }}</span></h1>
      <p>Seleccioná un módulo para comenzar</p>
    </div>

    <div class="dash-stats">
      <div class="stat-card">
        <span class="stat-icon"><app-icon name="grid" [size]="22" /></span>
        <div>
          <strong>{{ totalModulos }}</strong>
          <span>Módulos disponibles</span>
        </div>
      </div>
      <div class="stat-card">
        <span class="stat-icon" [class.status-ok]="backendStatus() === 'ok'" [class.status-error]="backendStatus() !== 'ok'">
          <app-icon [name]="backendStatus() === 'ok' ? 'check-circle' : 'alert-circle'" [size]="22" />
        </span>
        <div>
          <strong>{{ backendStatus() === 'ok' ? 'Activo' : 'Sin conexión' }}</strong>
          <span>Estado del sistema</span>
        </div>
      </div>
    </div>

    @for (grupo of grupos; track grupo.nombre) {
      <section class="dash-group">
        <h2>{{ grupo.nombre }}</h2>
        <div class="modules-grid">
          @for (m of grupo.modulos; track m.ruta) {
            <a [routerLink]="m.ruta" class="module-card">
              <span class="module-icon"><app-icon [name]="m.icono" [size]="22" /></span>
              <div class="module-text">
                <strong>{{ m.titulo }}</strong>
                <span>{{ m.descripcion }}</span>
              </div>
            </a>
          }
        </div>
      </section>
    }
  `,
  styleUrl: './admin-dashboard.scss',
})
export class AdminDashboard implements OnInit {
  private auth = inject(AuthService);
  private http = inject(HttpClient);

  backendStatus = signal<'checking' | 'ok' | 'error'>('checking');

  grupos: GrupoModulos[] = [
    {
      nombre: 'Gestión',
      modulos: [
        { ruta: 'usuarios', icono: 'users', titulo: 'Usuarios y roles', descripcion: 'Cuentas y permisos' },
        { ruta: 'sucursales', icono: 'store', titulo: 'Sucursales', descripcion: 'Tiendas de la cadena' },
        { ruta: 'proveedores', icono: 'truck', titulo: 'Proveedores', descripcion: 'Proveedores de prendas' },
      ],
    },
    {
      nombre: 'Catálogo maestro',
      modulos: [
        { ruta: 'catalogo/productos', icono: 'shirt', titulo: 'Productos', descripcion: 'Prendas del catálogo' },
        { ruta: 'catalogo/categorias', icono: 'tag', titulo: 'Categorías', descripcion: 'Tipos de prenda' },
        { ruta: 'catalogo/tallas', icono: 'ruler', titulo: 'Tallas', descripcion: 'Lista maestra de tallas' },
        { ruta: 'catalogo/colores', icono: 'palette', titulo: 'Colores', descripcion: 'Lista maestra de colores' },
        { ruta: 'catalogo/temporadas', icono: 'calendar', titulo: 'Temporadas', descripcion: 'Temporadas comerciales' },
        { ruta: 'catalogo/colecciones', icono: 'package', titulo: 'Colecciones', descripcion: 'Colecciones por temporada' },
      ],
    },
  ];

  get totalModulos(): number {
    return this.grupos.reduce((acc, g) => acc + g.modulos.length, 0);
  }

  nombre = () => this.auth.currentUser()?.nombre ?? 'Administrador';

  saludo(): string {
    const hora = new Date().getHours();
    if (hora < 12) return 'Buenos días';
    if (hora < 19) return 'Buenas tardes';
    return 'Buenas noches';
  }

  ngOnInit() {
    this.http.get<{ status: string }>(`${environment.apiUrl}/health`).subscribe({
      next: () => this.backendStatus.set('ok'),
      error: () => this.backendStatus.set('error'),
    });
  }
}
