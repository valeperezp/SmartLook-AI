import { DOCUMENT } from '@angular/common';
import { Injectable, inject, signal } from '@angular/core';
import { Observable, Subject } from 'rxjs';

/** Texto reconocido: `final` es false mientras la persona aún habla (resultado parcial). */
export interface TranscripcionVoz {
  texto: string;
  final: boolean;
}

/** Idiomas probados en orden: si el navegador no soporta es-BO se cae a es-ES. */
const IDIOMAS = ['es-BO', 'es-ES'];

/** Mensajes para cada código de error de la Web Speech API. `aborted` no es un error (lo provoca `detenerEscucha`). */
const ERRORES: Record<string, string> = {
  'not-allowed': 'Se denegó el acceso al micrófono. Habilitá el permiso en el navegador para dictar.',
  'service-not-allowed': 'El navegador no permite el dictado por voz en este sitio. Revisá los permisos del micrófono.',
  'audio-capture': 'No se detectó ningún micrófono. Conectá uno e intentá de nuevo.',
  'no-speech': 'No se escuchó nada. Probá de nuevo hablando cerca del micrófono.',
  network: 'No se pudo reconocer la voz: el servicio de dictado necesita conexión a internet.',
};

/**
 * Dictado por voz con la API nativa del navegador (`SpeechRecognition` / `webkitSpeechRecognition`):
 * no usa librerías externas ni servicios de pago.
 *
 * Uso: suscribirse a `transcripcion$` (emite en tiempo real) y llamar `iniciarEscucha()`.
 * `escuchando` y `error` son señales para pintar el estado en la pantalla.
 */
@Injectable({ providedIn: 'root' })
export class SpeechService {
  private ventana = inject(DOCUMENT).defaultView as (Window & Record<string, any>) | null;

  private emisor = new Subject<TranscripcionVoz>();
  private reconocimiento: any = null;
  private idioma = 0;

  /** Texto transcrito en tiempo real (parciales y final). */
  readonly transcripcion$: Observable<TranscripcionVoz> = this.emisor.asObservable();
  readonly escuchando = signal(false);
  /** Último error (permiso denegado, sin micrófono...). `null` si no hay ninguno. */
  readonly error = signal<string | null>(null);

  /** false si el navegador no tiene la API: la pantalla debe ocultar el micrófono. */
  get soportado(): boolean {
    return !!this.apiNavegador();
  }

  iniciarEscucha(): void {
    if (!this.soportado || this.escuchando()) return;
    this.error.set(null);
    this.idioma = 0;
    this.arrancar();
  }

  detenerEscucha(): void {
    // `stop` entrega el último resultado antes de cerrar; `abort` lo descartaría.
    try {
      this.reconocimiento?.stop();
    } catch {
      /* ya estaba detenido */
    }
    this.escuchando.set(false);
  }

  private apiNavegador(): (new () => any) | null {
    return this.ventana?.['SpeechRecognition'] || this.ventana?.['webkitSpeechRecognition'] || null;
  }

  private arrancar(): void {
    const Ctor = this.apiNavegador();
    if (!Ctor) return;
    const reconocimiento = new Ctor();
    this.reconocimiento = reconocimiento;
    reconocimiento.lang = IDIOMAS[this.idioma];
    reconocimiento.interimResults = true;
    reconocimiento.continuous = false;
    reconocimiento.maxAlternatives = 1;

    reconocimiento.onresult = (e: any) => {
      const resultados = Array.from(e.results as ArrayLike<any>);
      const texto = resultados.map((r) => r[0].transcript).join(' ').trim();
      if (texto) this.emisor.next({ texto, final: !!resultados[resultados.length - 1]?.isFinal });
    };
    reconocimiento.onerror = (e: any) => {
      const codigo: string = e?.error ?? '';
      if (codigo === 'aborted') return;
      if (codigo === 'language-not-supported' && this.idioma < IDIOMAS.length - 1) {
        this.idioma++;
        this.arrancar();
        return;
      }
      this.error.set(ERRORES[codigo] ?? 'No se pudo usar el dictado por voz.');
      this.escuchando.set(false);
    };
    reconocimiento.onend = () => {
      // Si hubo reintento de idioma, el reconocimiento vigente ya es otro: no se pisa su estado.
      if (this.reconocimiento === reconocimiento) this.escuchando.set(false);
    };

    try {
      reconocimiento.start();
      this.escuchando.set(true);
    } catch {
      this.error.set('No se pudo iniciar el micrófono.');
      this.escuchando.set(false);
    }
  }
}
