import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';
import { map } from 'rxjs';
import { AuthService } from '../services/auth.service';

/** Protege /login y /registro: si ya hay sesión, no tiene sentido mostrar el formulario. */
export const guestGuard: CanActivateFn = () => {
  const auth = inject(AuthService);
  const router = inject(Router);

  return auth.esperarSesion().pipe(
    map(() => {
      if (!auth.isLoggedIn()) return true;
      router.navigate(['/']);
      return false;
    })
  );
};
