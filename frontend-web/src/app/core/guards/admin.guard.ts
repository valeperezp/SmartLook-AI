import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';
import { map } from 'rxjs';
import { AuthService } from '../services/auth.service';

export const adminGuard: CanActivateFn = () => {
  const auth = inject(AuthService);
  const router = inject(Router);

  return auth.esperarSesion().pipe(
    map(() => {
      if (auth.isAdmin()) return true;
      router.navigate(auth.isLoggedIn() ? ['/'] : ['/login']);
      return false;
    })
  );
};
