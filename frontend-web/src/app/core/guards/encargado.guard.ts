import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';
import { map } from 'rxjs';
import { AuthService } from '../services/auth.service';

export const encargadoGuard: CanActivateFn = () => {
  const auth = inject(AuthService);
  const router = inject(Router);

  return auth.esperarSesion().pipe(
    map(() => {
      const user = auth.currentUser();
      if (!user) return router.parseUrl('/login');
      if (user.rol === 'encargado_sucursal' || user.rol === 'administrador') return true;
      return router.parseUrl('/');
    })
  );
};
