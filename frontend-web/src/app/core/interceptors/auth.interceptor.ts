import { HttpErrorResponse, HttpInterceptorFn } from '@angular/common/http';
import { inject } from '@angular/core';
import { catchError, throwError } from 'rxjs';
import { AuthService } from '../services/auth.service';

// Un 401 en estas rutas no significa "sesión vencida": credenciales erróneas (login/registro)
// o la restauración de sesión al arrancar, que ya maneja AuthService.esperarSesion().
const RUTAS_SIN_LOGOUT = ['/auth/login', '/auth/registro', '/auth/me'];

export const authInterceptor: HttpInterceptorFn = (req, next) => {
  const auth = inject(AuthService);
  const token = auth.getToken();

  if (!token) {
    // Sin sesión: el backend muestra el catálogo de la tienda indicada (o la tienda por defecto).
    const empresa = auth.getEmpresaVisitada();
    return next(empresa ? req.clone({ setHeaders: { 'X-Empresa': empresa } }) : req);
  }

  return next(
    req.clone({
      setHeaders: { Authorization: `Bearer ${token}` },
    })
  ).pipe(
    catchError((err: unknown) => {
      // Sesión vencida o inválida: cerrar sesión y volver al login. Se comprueba el token otra vez
      // para que varios 401 simultáneos solo disparen un logout.
      if (
        err instanceof HttpErrorResponse &&
        err.status === 401 &&
        !RUTAS_SIN_LOGOUT.some((ruta) => req.url.includes(ruta)) &&
        auth.getToken()
      ) {
        auth.logout();
      }
      return throwError(() => err);
    })
  );
};
