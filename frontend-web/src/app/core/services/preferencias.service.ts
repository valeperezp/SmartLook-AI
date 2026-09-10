import { Injectable, effect, signal } from '@angular/core';

export type Tema = 'light' | 'dark';

const STORAGE_KEY = 'smartlook_tema';

function temaInicial(): Tema {
  const guardado = localStorage.getItem(STORAGE_KEY);
  if (guardado === 'light' || guardado === 'dark') return guardado;
  return window.matchMedia?.('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
}

@Injectable({ providedIn: 'root' })
export class PreferenciasService {
  tema = signal<Tema>(temaInicial());

  constructor() {
    // Aplica al DOM y persiste cada vez que cambia (incluida la carga inicial).
    effect(() => {
      const tema = this.tema();
      document.documentElement.setAttribute('data-theme', tema);
      localStorage.setItem(STORAGE_KEY, tema);
    });
  }

  toggleTema() {
    this.tema.update((t) => (t === 'dark' ? 'light' : 'dark'));
  }
}
