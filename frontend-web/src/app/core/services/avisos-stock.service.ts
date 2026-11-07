import { HttpErrorResponse } from '@angular/common/http';
import { Injectable, computed, inject, signal } from '@angular/core';
import { firstValueFrom } from 'rxjs';
import { Suscripcion, SuscripcionPendienteLocal } from '../models/suscripcion.model';
import { AuthService } from './auth.service';
import { OfflineDbService } from './offline-db.service';
import { SuscripcionesService } from './suscripciones.service';

/** Qué pasó al pedir "Avísame cuando llegue". */
export interface ResultadoAviso {
  resultado: 'enviada' | 'guardada' | 'ya-llego' | 'error';
  mensaje: string;
}

export const MENSAJE_LLEGO = '¡Llegó el producto que esperabas!';

/**
 * "Avísame cuando llegue" (CU16) en la web: el cliente se suscribe a una prenda agotada y el servidor le avisa cuando entra
 * stock. Sin conexión la suscripción se guarda en IndexedDB y se envía sola al volver la red.
 *
 * Guarda el estado que usan la campana del menú, la pantalla "Mis notificaciones" y el aviso "¡Llegó el producto que esperabas!".
 */
@Injectable({ providedIn: 'root' })
export class AvisosStockService {
  private api = inject(SuscripcionesService);
  private db = inject(OfflineDbService);
  private auth = inject(AuthService);

  /** Todas las suscripciones del cliente (pendientes y notificadas). */
  readonly mias = signal<Suscripcion[]>([]);
  /** Suscripciones hechas sin conexión que todavía no se enviaron. */
  readonly pendientesLocales = signal<SuscripcionPendienteLocal[]>([]);
  /** Los avisos: prendas que esperaba y ya llegaron. */
  readonly notificaciones = computed(() => this.mias().filter((s) => s.estado === 'notificado'));
  /** Los que el cliente todavía no vio: es el número de la campana. */
  readonly sinVer = computed(() => this.notificaciones().filter((s) => !s.visto).length);
  /** Aviso flotante "¡Llegó el producto que esperabas!" (null = no hay). */
  readonly toast = signal<string | null>(null);

  private mostradas = new Set<number>();
  private ocupado = false;
  private temporizadorToast: ReturnType<typeof setTimeout> | null = null;

  constructor() {
    if (typeof window !== 'undefined') window.addEventListener('online', () => void this.refrescar());
  }

  /** ¿El cliente ya está esperando esta prenda (pedida a cualquier talla/color/sucursal)? */
  espera(productoId: number): boolean {
    return (
      this.mias().some((s) => s.producto_id === productoId && s.estado === 'pendiente') ||
      this.pendientesLocales().some((s) => s.producto_id === productoId)
    );
  }

  // ---------- suscribirse ----------
  async suscribirse(
    producto: { id: number; nombre: string },
    opciones: { talla_id?: number | null; color_id?: number | null; sucursal_id?: number | null } = {},
  ): Promise<ResultadoAviso> {
    const cliente = this.auth.currentUser();
    if (!cliente || !this.auth.isCliente()) {
      return { resultado: 'error', mensaje: 'Solo los clientes con sesión iniciada pueden pedir avisos.' };
    }
    const cuerpo = {
      producto_id: producto.id,
      talla_id: opciones.talla_id ?? null,
      color_id: opciones.color_id ?? null,
      sucursal_id: opciones.sucursal_id ?? null,
    };
    if (this.sinRed()) return this.guardarSinConexion(cliente.id, producto.nombre, cuerpo);

    try {
      const s = await firstValueFrom(this.api.suscribirse(cuerpo));
      this.mias.update((lista) => [s, ...lista.filter((x) => x.id !== s.id)]);
      if (s.estado === 'notificado') return { resultado: 'ya-llego', mensaje: `¡"${producto.nombre}" ya tiene stock!` };
      return { resultado: 'enviada', mensaje: `Te avisaremos cuando llegue "${producto.nombre}".` };
    } catch (error) {
      // Sin red o con el servidor caído: no se pierde, se guarda y se envía luego. Un 4xx sí es un rechazo real.
      if (error instanceof HttpErrorResponse && error.status >= 400 && error.status < 500) {
        return { resultado: 'error', mensaje: error.error?.detail || 'No se pudo guardar el aviso.' };
      }
      return this.guardarSinConexion(cliente.id, producto.nombre, cuerpo);
    }
  }

  private async guardarSinConexion(
    clienteId: number,
    nombre: string,
    cuerpo: { producto_id: number; talla_id: number | null; color_id: number | null; sucursal_id: number | null },
  ): Promise<ResultadoAviso> {
    try {
      await this.db.guardarSuscripcionPendiente({ cliente_id: clienteId, nombre_producto: nombre, ...cuerpo });
      await this.leerPendientesLocales();
      return { resultado: 'guardada', mensaje: `Sin conexión: tu aviso de "${nombre}" quedó guardado y se enviará al volver la red.` };
    } catch {
      return { resultado: 'error', mensaje: 'No se pudo guardar el aviso en este dispositivo.' };
    }
  }

  // ---------- sincronizar y consultar ----------
  /** Envía lo guardado sin conexión, vuelve a leer los avisos y, si llegó algo nuevo, muestra "¡Llegó el producto que esperabas!". */
  async refrescar(): Promise<void> {
    if (!this.auth.isCliente()) {
      this.mias.set([]);
      this.pendientesLocales.set([]);
      return;
    }
    if (this.ocupado) return;
    this.ocupado = true;
    try {
      await this.leerPendientesLocales();
      if (this.sinRed()) return;
      await this.enviarPendientes();
      const lista = await firstValueFrom(this.api.mias());
      this.mias.set(lista);
      const nuevas = lista.filter((s) => s.estado === 'notificado' && !s.visto && !this.mostradas.has(s.id));
      if (nuevas.length > 0) {
        nuevas.forEach((s) => this.mostradas.add(s.id));
        this.toast.set(MENSAJE_LLEGO);
        if (this.temporizadorToast) clearTimeout(this.temporizadorToast);
        this.temporizadorToast = setTimeout(() => this.toast.set(null), 10_000); // se cierra solo
      }
    } catch {
      // sin servidor: se conserva lo que había y se reintenta con el próximo evento
    } finally {
      this.ocupado = false;
    }
  }

  private async enviarPendientes(): Promise<void> {
    const clienteId = this.auth.currentUser()?.id ?? null;
    for (const p of await this.db.obtenerSuscripcionesPendientes(clienteId)) {
      try {
        const s = await firstValueFrom(
          this.api.suscribirse({ producto_id: p.producto_id, talla_id: p.talla_id, color_id: p.color_id, sucursal_id: p.sucursal_id, uuid: p.uuid }),
        );
        this.mias.update((lista) => [s, ...lista.filter((x) => x.id !== s.id)]);
        await this.db.eliminarSuscripcionPendiente(p.uuid);
      } catch (error) {
        // Un 4xx nunca va a funcionar (producto que ya no existe...): se descarta. Cualquier otro error: se reintenta luego.
        if (error instanceof HttpErrorResponse && error.status >= 400 && error.status < 500) {
          await this.db.eliminarSuscripcionPendiente(p.uuid);
        } else {
          break;
        }
      }
    }
    await this.leerPendientesLocales();
  }

  private async leerPendientesLocales(): Promise<void> {
    try {
      this.pendientesLocales.set(await this.db.obtenerSuscripcionesPendientes(this.auth.currentUser()?.id ?? null));
    } catch {
      this.pendientesLocales.set([]);
    }
  }

  /** El cliente ya vio sus avisos (abrió "Mis notificaciones"): la campana vuelve a 0. */
  async marcarVistas(): Promise<void> {
    if (this.sinVer() === 0) return;
    this.mias.update((lista) => lista.map((s) => (s.estado === 'notificado' ? { ...s, visto: true } : s)));
    try {
      await firstValueFrom(this.api.marcarVistas());
    } catch {
      // se vuelve a marcar la próxima vez
    }
  }

  cerrarToast() {
    if (this.temporizadorToast) clearTimeout(this.temporizadorToast);
    this.temporizadorToast = null;
    this.toast.set(null);
  }

  /** Consulta los avisos cada [cada] ms mientras la app esté abierta. Devuelve la función que lo detiene. */
  iniciarSondeo(cada = 120_000): () => void {
    const id = setInterval(() => void this.refrescar(), cada);
    return () => clearInterval(id);
  }

  private sinRed(): boolean {
    return typeof navigator !== 'undefined' && navigator.onLine === false;
  }
}
