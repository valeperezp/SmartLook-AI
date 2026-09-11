import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';
import { map } from 'rxjs';
import { AuthService } from '../services/auth.service';

export const homeGuard: CanActivateFn = () => {
  const auth = inject(AuthService);
  const router = inject(Router);

  return auth.esperarSesion().pipe(
    map(() => {
      // Sin sesión: catálogo público, dejar pasar
      if (!auth.isLoggedIn()) {
        return true;
      }
      // Admin, encargado y proveedor van a sus paneles
      if (auth.isAdmin() || auth.isEncargado() || auth.isProveedor()) {
        router.navigate([auth.getHomeRoute()]);
        return false;
      }
      // Cliente logueado: ve el catálogo normal
      return true;
    })
  );
};
