import { Injectable, computed, inject, signal } from '@angular/core';
import { HttpClient, HttpErrorResponse } from '@angular/common/http';
import { Router } from '@angular/router';
import { catchError, of, shareReplay, switchMap, tap } from 'rxjs';
import { environment } from '../../../environments/environment';
import { Usuario } from '../models/usuario.model';

const TOKEN_KEY = 'smartlook_token';
const EMPRESA_KEY = 'smartlook_empresa';
export const AVISO_CERRADO_KEY = 'smartlook_aviso_vencimiento_cerrado';

interface TokenResponse {
  access_token: string;
  token_type: string;
}

@Injectable({ providedIn: 'root' })
export class AuthService {
  private http = inject(HttpClient);
  private router = inject(Router);
  private readonly apiUrl = environment.apiUrl;

  currentUser = signal<Usuario | null>(null);
  isLoggedIn = computed(() => this.currentUser() !== null);
  isAdmin = computed(() => this.currentUser()?.rol === 'administrador');
  isEncargado = computed(() => this.currentUser()?.rol === 'encargado_sucursal');
  isProveedor = computed(() => this.currentUser()?.rol === 'proveedor');
  isCliente = computed(() => this.currentUser()?.rol === 'cliente');
  isCajero = computed(() => this.currentUser()?.rol === 'cajero');
  isSuperadmin = computed(() => this.currentUser()?.rol === 'superadmin');

  getHomeRoute(): string {
    const user = this.currentUser();
    if (!user) return '/login';
    if (user.rol === 'superadmin') return '/plataforma';
    if (user.rol === 'administrador') return '/admin';
    if (user.rol === 'encargado_sucursal') return '/encargado';
    if (user.rol === 'proveedor') return '/proveedor';
    if (user.rol === 'cajero') return '/cajero';
    return '/';
  }

  getToken(): string | null {
    return localStorage.getItem(TOKEN_KEY);
  }

  /** Tienda (slug) que el visitante eligió con /login?empresa=..., para navegar sin sesión. */
  getEmpresaVisitada(): string | null {
    try {
      return localStorage.getItem(EMPRESA_KEY);
    } catch {
      return null;
    }
  }

  setEmpresaVisitada(slug: string | null) {
    try {
      if (slug) localStorage.setItem(EMPRESA_KEY, slug);
      else localStorage.removeItem(EMPRESA_KEY);
    } catch {
      // almacenamiento bloqueado: se usa la tienda por defecto
    }
  }

  private setToken(token: string) {
    localStorage.setItem(TOKEN_KEY, token);
  }

  private clearToken() {
    localStorage.removeItem(TOKEN_KEY);
  }

  /**
   * Login + obtiene el usuario logueado. Devuelve el Usuario ya con la sesión guardada.
   * `empresa` (slug) es opcional: si viene, el usuario tiene que pertenecer a esa empresa (CU1).
   */
  login(email: string, password: string, empresa?: string | null) {
    const body = new URLSearchParams();
    body.set('username', email);
    body.set('password', password);
    if (empresa) body.set('empresa', empresa);

    return this.http
      .post<TokenResponse>(`${this.apiUrl}/auth/login`, body.toString(), {
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      })
      .pipe(
        tap((res) => {
          this.setToken(res.access_token);
          // CU1 8a: el aviso de vencimiento cerrado vuelve a mostrarse en cada inicio de sesión.
          try { sessionStorage.removeItem(AVISO_CERRADO_KEY); } catch { /* sin almacenamiento */ }
        }),
        switchMap(() => this.http.get<Usuario>(`${this.apiUrl}/auth/me`)),
        tap((usuario) => this.currentUser.set(usuario))
      );
  }

  registrar(nombre: string, email: string, password: string) {
    // El cliente queda registrado en la tienda que está visitando (o la tienda por defecto).
    const empresa = this.getEmpresaVisitada();
    return this.http.post<Usuario>(`${this.apiUrl}/auth/registro`, { nombre, email, password, empresa });
  }

  refrescarUsuario() {
    return this.http.get<Usuario>(`${this.apiUrl}/auth/me`).pipe(
      tap((usuario) => this.currentUser.set(usuario))
    );
  }

  /**
   * Restaura la sesión desde el token guardado. `shareReplay(1)` la convierte en un
   * observable "memoizado": se dispara una sola vez y cualquiera que la escuche después
   * (el APP_INITIALIZER, los guards) recibe el mismo resultado ya resuelto, sin depender
   * del orden en que arrancan (los APP_INITIALIZER corren en paralelo, no en secuencia).
   */
  private sesionLista$ = (() => {
    const token = this.getToken();
    if (!token) return of(null);

    return this.http.get<Usuario>(`${this.apiUrl}/auth/me`).pipe(
      tap((usuario) => this.currentUser.set(usuario)),
      catchError((err) => {
        // Solo un 401 significa token invalido/expirado. Red caida, timeout, 5xx o cold start del backend
        // no deben cerrar la sesion: el token se conserva y el proximo request reintenta.
        if (err instanceof HttpErrorResponse && err.status === 401) {
          this.clearToken();
        }
        return of(null);
      }),
      shareReplay(1)
    );
  })();

  /** Usalo antes de evaluar isLoggedIn()/isAdmin() en un guard o en el bootstrap. */
  esperarSesion() {
    return this.sesionLista$;
  }

  logout() {
    this.clearToken();
    this.currentUser.set(null);
    // Navega directo a /login (no a '/'): si ya estábamos en '/', Angular
    // trata "misma URL" como no-op y no vuelve a evaluar el guard.
    this.router.navigate(['/login']);
  }
}
