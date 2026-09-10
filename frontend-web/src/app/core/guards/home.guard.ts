import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';
import { map } from 'rxjs';
import { AuthService } from '../services/auth.service';

/**
 * Guard de la home ('/'): el cliente la ve normal, pero el administrador
 * no tiene "su" contenido ahí — se lo manda directo al panel de gestión.
 */
export const homeGuard: CanActivateFn = () => {
  const auth = inject(AuthService);
  const router = inject(Router);

  return auth.esperarSesion().pipe(
    map(() => {
      if (!auth.isLoggedIn()) {
        router.navigate(['/login']);
        return false;
      }
      if (auth.isAdmin()) {
        router.navigate(['/admin']);
        return false;
      }
      if (auth.isEncargado()) {
        router.navigate(['/encargado']);
        return false;
      }
      return true;
    })
  );
};
