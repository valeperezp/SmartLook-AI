import { Injectable, computed, inject, signal } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Router } from '@angular/router';
import { catchError, of, shareReplay, switchMap, tap } from 'rxjs';
import { environment } from '../../../environments/environment';
import { Usuario } from '../models/usuario.model';

const TOKEN_KEY = 'smartlook_token';

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

  getHomeRoute(): string {
    const user = this.currentUser();
    if (!user) return '/login';
    if (user.rol === 'administrador') return '/admin';
    if (user.rol === 'encargado_sucursal') return '/encargado';
    if (user.rol === 'proveedor') return '/proveedor';
    return '/';
  }

  getToken(): string | null {
    return localStorage.getItem(TOKEN_KEY);
  }

  private setToken(token: string) {
    localStorage.setItem(TOKEN_KEY, token);
  }

  private clearToken() {
    localStorage.removeItem(TOKEN_KEY);
  }

  /** Login + obtiene el usuario logueado. Devuelve el Usuario ya con la sesión guardada. */
  login(email: string, password: string) {
    const body = new URLSearchParams();
    body.set('username', email);
    body.set('password', password);

    return this.http
      .post<TokenResponse>(`${this.apiUrl}/auth/login`, body.toString(), {
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      })
      .pipe(
        tap((res) => this.setToken(res.access_token)),
        switchMap(() => this.http.get<Usuario>(`${this.apiUrl}/auth/me`)),
        tap((usuario) => this.currentUser.set(usuario))
      );
  }

  registrar(nombre: string, email: string, password: string) {
    return this.http.post<Usuario>(`${this.apiUrl}/auth/registro`, { nombre, email, password });
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
      catchError(() => {
        this.clearToken();
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
