import { ApplicationConfig, inject, isDevMode, provideAppInitializer, provideBrowserGlobalErrorListeners } from '@angular/core';
import { provideRouter, withEnabledBlockingInitialNavigation } from '@angular/router';
import { provideHttpClient, withInterceptors } from '@angular/common/http';
import { provideServiceWorker } from '@angular/service-worker';
import { firstValueFrom } from 'rxjs';
import { routes } from './app.routes';
import { authInterceptor } from './core/interceptors/auth.interceptor';
import { AuthService } from './core/services/auth.service';
import { PreferenciasService } from './core/services/preferencias.service';

export const appConfig: ApplicationConfig = {
  providers: [
    provideBrowserGlobalErrorListeners(),
    provideRouter(routes, withEnabledBlockingInitialNavigation()),
    provideHttpClient(withInterceptors([authInterceptor])),
    provideAppInitializer(() => {
      const auth = inject(AuthService);
      return firstValueFrom(auth.esperarSesion());
    }),
    provideAppInitializer(() => {
      // Solo con inyectarlo alcanza: su constructor aplica tema/tamaño de texto al DOM
      // antes del primer render, evitando un flash del valor por defecto.
      inject(PreferenciasService);
    }),
    // PWA: el Service Worker solo se registra en producción (en desarrollo molestaría con la caché)
    provideServiceWorker('ngsw-worker.js', {
      enabled: !isDevMode(),
      registrationStrategy: 'registerWhenStable:30000',
    }),
  ],
};

