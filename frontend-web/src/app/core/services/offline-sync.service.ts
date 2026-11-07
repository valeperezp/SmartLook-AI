import { HttpClient, HttpErrorResponse } from '@angular/common/http';
import { Injectable, inject, signal } from '@angular/core';
import { firstValueFrom, timeout } from 'rxjs';
import { environment } from '../../../environments/environment';
import { Categoria, Producto, ProductoDisponibilidad } from '../models/catalogo.model';
import {
  ItemCatalogoLocal,
  NuevaOperacionLocal,
  OperacionLocal,
  OperacionSyncPayload,
  ResultadoSyncItem,
  ResultadoSyncWeb,
} from '../models/offline.model';
import { Sucursal } from '../models/sucursal.model';
import { AuthService } from './auth.service';
import { CatalogoService } from './catalogo.service';
import { OfflineDbService } from './offline-db.service';

/** Cuánto se espera, tras volver la red, SIN nuevos cambios antes de sincronizar (un wifi que parpadea reinicia la espera). */
const ESPERA_TRAS_RECONEXION_MS = 3000;
const TIMEOUT_ENVIO_MS = 30_000;
/** Cuántas disponibilidades se piden a la vez al descargar el catálogo (una por producto). */
const PARALELISMO_DESCARGA = 6;

const RESULTADO_VACIO: ResultadoSyncWeb = {
  sincronizadas: 0,
  rechazadas: 0,
  enConflicto: 0,
  fallidas: 0,
  enEspera: 0,
  sinRed: false,
  sesionExpirada: false,
  yaEnCurso: false,
};

/**
 * Sincronización de la web offline: guarda el catálogo en IndexedDB y, cuando vuelve la conexión (evento `online`),
 * envía las operaciones pendientes a `POST /sync/operaciones` con el mismo JSON que la app móvil.
 *
 * Contrato con el backend (por operación): `ok` → sincronizada · `conflict` → rechazada · `en_conflicto` → guardada sin
 * stock, la resuelve un encargado · `pendiente` → sigue pendiente
 * con el mensaje del servidor. Un 401 (sesión vencida), un error de red, un timeout, un 404 o un 5xx dejan TODO pendiente:
 * nunca se pierde una operación.
 */
@Injectable({ providedIn: 'root' })
export class OfflineSyncService {
  private http = inject(HttpClient);
  private db = inject(OfflineDbService);
  private auth = inject(AuthService);
  private catalogo = inject(CatalogoService);

  /** ¿Hay conexión? (navigator.onLine + eventos online/offline). Alimenta el banner "Modo Offline". */
  readonly online = signal(typeof navigator === 'undefined' ? true : navigator.onLine);
  readonly pendientes = signal(0);
  readonly sincronizando = signal(false);
  readonly descargando = signal(false);
  /** Resumen legible de la última sincronización. */
  readonly ultimoMensaje = signal<string | null>(null);
  /** Variantes del catálogo guardadas para esta tienda y cuándo se descargaron. */
  readonly variantesOffline = signal(0);
  readonly catalogoDescargadoEn = signal<string | null>(null);
  /**
   * Sube cada vez que cambia el catálogo local (se descargó, una operación offline descontó stock o un rechazo lo
   * devolvió). Las pantallas que muestran el catálogo guardado lo observan para volver a leerlo.
   */
  readonly catalogoVersion = signal(0);

  private enCurso = false;
  private temporizador: ReturnType<typeof setTimeout> | null = null;

  constructor() {
    if (typeof window !== 'undefined') {
      window.addEventListener('online', this.alVolverLaRed);
      window.addEventListener('offline', this.alPerderLaRed);
    }
    void this.refrescarEstado();
    if (this.online()) this.programarSincronizacion(); // lo que quedó pendiente de una sesión anterior
  }

  private alVolverLaRed = () => {
    this.online.set(true);
    this.programarSincronizacion();
  };

  private alPerderLaRed = () => {
    this.online.set(false);
    this.cancelarTemporizador(); // se cayó otra vez antes de que se cumpliera la espera
  };

  private programarSincronizacion(espera = ESPERA_TRAS_RECONEXION_MS) {
    this.cancelarTemporizador();
    this.temporizador = setTimeout(() => {
      this.temporizador = null;
      void this.sincronizarPendientes();
    }, espera);
  }

  private cancelarTemporizador() {
    if (this.temporizador) clearTimeout(this.temporizador);
    this.temporizador = null;
  }

  // ---------------------------------------------------------------------------
  // Catálogo
  // ---------------------------------------------------------------------------

  /** Tienda actual: la del usuario con sesión o, si no, la que eligió el visitante (por defecto `smartlook`). */
  empresaActual(): string {
    return String(this.auth.currentUser()?.empresa_id ?? this.auth.getEmpresaVisitada() ?? 'smartlook');
  }

  /**
   * Descarga el catálogo del backend (productos + disponibilidad por sucursal, talla y color) y lo guarda en
   * IndexedDB para consultarlo sin conexión. Devuelve cuántas variantes quedaron guardadas.
   */
  async descargarCatalogo(): Promise<number> {
    if (!this.online()) throw new Error('Sin conexión: conéctate a internet para descargar el catálogo.');
    this.descargando.set(true);
    try {
      const productos = (await firstValueFrom(this.catalogo.listarProductos(false))).filter((p) => p.activo !== false);
      const disponibilidades = await this.enTandas(productos, PARALELISMO_DESCARGA, (p) =>
        firstValueFrom(this.catalogo.obtenerDisponibilidad(p.id)),
      );
      const empresa = this.empresaActual();
      const items = OfflineSyncService.construirItemsCatalogo(productos, disponibilidades, empresa);
      const guardadas = await this.db.guardarCatalogo(items, empresa);
      await this.refrescarEstado();
      return guardadas;
    } finally {
      this.descargando.set(false);
    }
  }

  /** Convierte la respuesta del backend en filas de `catalogo_local` (una por sucursal + producto + talla + color). */
  static construirItemsCatalogo(productos: Producto[], disponibilidades: ProductoDisponibilidad[], empresa: string): ItemCatalogoLocal[] {
    const ahora = new Date().toISOString();
    const porProducto = new Map(productos.map((p) => [p.id, p]));
    const filas = new Map<string, ItemCatalogoLocal>();
    for (const d of disponibilidades) {
      const p = porProducto.get(d.producto_id);
      if (!p) continue;
      for (const suc of d.disponibilidad) {
        for (const it of suc.items) {
          const clave = OfflineDbService.claveCatalogo(empresa, suc.sucursal_id, d.producto_id, it.talla_id, it.color_id);
          filas.set(clave, {
            clave,
            empresa,
            sucursal_id: suc.sucursal_id,
            nombre_sucursal: suc.nombre_sucursal,
            producto_id: d.producto_id,
            nombre_producto: p.nombre,
            descripcion: p.descripcion ?? null,
            categoria_id: p.categoria_id ?? null,
            nombre_categoria: p.categoria?.nombre ?? null,
            talla_id: it.talla_id,
            nombre_talla: it.nombre_talla,
            color_id: it.color_id,
            nombre_color: it.nombre_color,
            precio_centavos: Math.round(Number(p.precio) * 100),
            imagen_url: p.imagen_url ?? null,
            cantidad_disponible: Math.max(0, it.cantidad_disponible),
            sincronizado_en: ahora,
          });
        }
      }
    }
    return [...filas.values()];
  }

  /**
   * El catálogo guardado en formato de la pantalla del catálogo (productos, categorías y sucursales), para mostrarlo
   * cuando no hay red. Null si nunca se descargó nada para esta tienda.
   */
  async leerCatalogoLocal(): Promise<{ productos: Producto[]; categorias: Categoria[]; sucursales: Sucursal[] } | null> {
    const filas = await this.db.obtenerCatalogo(this.empresaActual());
    if (filas.length === 0) return null;

    const productos = new Map<number, Producto>();
    const sucursalesConStock = new Map<number, Set<number>>();
    const categorias = new Map<number, Categoria>();
    const sucursales = new Map<number, Sucursal>();
    for (const f of filas) {
      let p = productos.get(f.producto_id);
      if (!p) {
        const categoria: Categoria = { id: f.categoria_id ?? 0, nombre: f.nombre_categoria ?? 'Sin categoría', activo: true };
        p = {
          id: f.producto_id,
          nombre: f.nombre_producto,
          descripcion: f.descripcion ?? undefined,
          precio: f.precio_centavos / 100,
          categoria_id: categoria.id,
          imagen_url: f.imagen_url ?? undefined,
          activo: true,
          categoria,
          total_disponible: 0,
          sucursales_con_stock: 0,
          estado_global: 'agotado',
        };
        productos.set(f.producto_id, p);
        if (f.categoria_id !== null) categorias.set(categoria.id, categoria);
      }
      p.total_disponible = (p.total_disponible ?? 0) + f.cantidad_disponible;
      if (f.cantidad_disponible > 0) {
        const conStock = sucursalesConStock.get(f.producto_id) ?? new Set<number>();
        conStock.add(f.sucursal_id);
        sucursalesConStock.set(f.producto_id, conStock);
      }
      sucursales.set(f.sucursal_id, { id: f.sucursal_id, nombre: f.nombre_sucursal, direccion: '', activa: true });
    }
    for (const p of productos.values()) {
      p.sucursales_con_stock = sucursalesConStock.get(p.id)?.size ?? 0;
      p.estado_global = !p.total_disponible ? 'agotado' : p.total_disponible <= 5 ? 'bajo' : 'disponible';
    }
    return { productos: [...productos.values()], categorias: [...categorias.values()], sucursales: [...sucursales.values()] };
  }

  // ---------------------------------------------------------------------------
  // Operaciones
  // ---------------------------------------------------------------------------

  /** Guarda una operación hecha (o por enviar) y, si hay red, programa su envío. Devuelve el uuid. */
  async registrarOperacion(nueva: NuevaOperacionLocal): Promise<string> {
    const uuid = await this.db.guardarOperacionLocal(nueva, this.auth.currentUser()?.id ?? null);
    await this.refrescarEstado();
    if (this.online()) this.programarSincronizacion();
    return uuid;
  }

  /** Envía a `POST /sync/operaciones` las operaciones pendientes del usuario actual y actualiza sus estados en IndexedDB. */
  async sincronizarPendientes(): Promise<ResultadoSyncWeb> {
    if (this.enCurso) return { ...RESULTADO_VACIO, yaEnCurso: true };
    if (!this.online()) return this.terminar({ ...RESULTADO_VACIO, sinRed: true });
    const usuario = this.auth.currentUser();
    if (!usuario || !this.auth.getToken()) return this.terminar({ ...RESULTADO_VACIO, sesionExpirada: true });

    this.enCurso = true;
    this.sincronizando.set(true);
    try {
      await this.db.liberarOperacionesEnProceso();
      const pendientes = await this.db.obtenerOperacionesPendientes(usuario.id);
      if (pendientes.length === 0) return this.terminar(RESULTADO_VACIO);
      const uuids = pendientes.map((o) => o.uuid);
      await this.db.marcarEnProceso(uuids); // suma un intento a cada una

      let resultados: ResultadoSyncItem[];
      try {
        const respuesta = await firstValueFrom(
          this.http
            .post<{ resultados?: ResultadoSyncItem[] }>(`${environment.apiUrl}/sync/operaciones`, {
              enviado_en: new Date().toISOString(),
              operaciones: pendientes.map(OfflineSyncService.aPayload),
            })
            .pipe(timeout(TIMEOUT_ENVIO_MS)),
        );
        resultados = respuesta?.resultados ?? [];
      } catch (error) {
        return this.terminar(await this.fallarEnvio(uuids, error));
      }
      return this.terminar(await this.procesarRespuesta(pendientes, resultados));
    } finally {
      this.enCurso = false;
      this.sincronizando.set(false);
      await this.refrescarEstado();
    }
  }

  /** El JSON de una operación: igual al que arma el `SyncService` del móvil. */
  static aPayload(o: OperacionLocal): OperacionSyncPayload {
    return {
      uuid: o.uuid,
      tipo_operacion: o.tipo_operacion,
      sucursal_id: o.sucursal_id,
      cajero_id: o.cajero_id,
      cliente_id: o.cliente_id,
      fecha: o.fecha,
      total_centavos: o.total_centavos,
      items: o.items.map((i) => ({
        producto_id: i.producto_id,
        talla_id: i.talla_id,
        color_id: i.color_id,
        cantidad: i.cantidad,
        precio_unitario_centavos: i.precio_unitario_centavos,
      })),
    };
  }

  /** El envío falló: todo vuelve a 'pendiente' (nada se pierde) con el motivo. Un 401 detiene la sincronización. */
  private async fallarEnvio(uuids: string[], error: unknown): Promise<ResultadoSyncWeb> {
    const status = error instanceof HttpErrorResponse ? error.status : null;
    let motivo: string;
    let resultado: ResultadoSyncWeb = { ...RESULTADO_VACIO, fallidas: uuids.length };
    if (status === 401) {
      motivo = 'Sesión expirada: vuelve a iniciar sesión.';
      resultado = { ...RESULTADO_VACIO, sesionExpirada: true };
    } else if (status === 0) {
      motivo = 'Error de envío: sin conexión con el servidor.';
      resultado = { ...resultado, sinRed: true };
    } else if (status === 404) {
      motivo = 'El servidor aún no tiene /sync/operaciones (404).';
    } else if (status !== null) {
      motivo = `Error de envío: el servidor respondió ${status}.`;
    } else {
      motivo = `Error de envío: ${error instanceof Error ? error.message : 'desconocido'}.`;
    }
    for (const uuid of uuids) await this.db.devolverAPendiente(uuid, motivo);
    return resultado;
  }

  private async procesarRespuesta(pendientes: OperacionLocal[], resultados: ResultadoSyncItem[]): Promise<ResultadoSyncWeb> {
    const porUuid = new Map(resultados.map((r) => [r.uuid, r]));
    const total = { ...RESULTADO_VACIO };
    for (const op of pendientes) {
      const r = porUuid.get(op.uuid);
      try {
        if (r?.status === 'ok' && typeof r.id_servidor === 'number') {
          await this.db.marcarSincronizada(op.uuid, r.id_servidor);
          total.sincronizadas++;
        } else if (r?.status === 'conflict') {
          await this.db.marcarRechazada(op.uuid, r.message ?? 'Rechazada por el servidor');
          total.rechazadas++;
        } else if (r?.status === 'en_conflicto') {
          // Sin stock en el servidor: la venta quedó guardada allá, "en conflicto", para que un encargado la resuelva.
          // El stock local NO se devuelve (la venta ya se hizo) y no se reenvía.
          await this.db.marcarEnConflicto(op.uuid, r.message ?? 'En conflicto de stock', typeof r.id_servidor === 'number' ? r.id_servidor : null);
          total.enConflicto++;
        } else if (r?.status === 'pendiente') {
          await this.db.devolverAPendiente(op.uuid, r.message ?? 'En espera de otra operación'); // no es error ni rechazo
          total.enEspera++;
        } else {
          throw new Error(`respuesta desconocida del servidor: ${r?.status ?? 'sin resultado'}`);
        }
      } catch (error) {
        await this.db.devolverAPendiente(op.uuid, `Respuesta no procesada: ${error instanceof Error ? error.message : error}`);
        total.fallidas++;
      }
    }
    return total;
  }

  private terminar(r: ResultadoSyncWeb): ResultadoSyncWeb {
    this.ultimoMensaje.set(OfflineSyncService.resumen(r));
    return r;
  }

  static resumen(r: ResultadoSyncWeb): string {
    if (r.yaEnCurso) return 'Ya hay una sincronización en curso.';
    if (r.sinRed && r.fallidas === 0) return 'Sin conexión: no se sincronizó nada.';
    if (r.sesionExpirada) return 'Sesión expirada: vuelve a iniciar sesión. Tus operaciones siguen guardadas en el navegador.';
    const partes = [
      r.sincronizadas > 0 ? `${r.sincronizadas} ${r.sincronizadas === 1 ? 'sincronizada' : 'sincronizadas'}` : '',
      r.rechazadas > 0 ? `${r.rechazadas} ${r.rechazadas === 1 ? 'rechazada' : 'rechazadas'}` : '',
      r.enConflicto > 0 ? `${r.enConflicto} en conflicto (la resuelve el encargado)` : '',
      r.fallidas > 0 ? `${r.fallidas} ${r.fallidas === 1 ? 'pendiente de reintentar' : 'pendientes de reintentar'}` : '',
      r.enEspera > 0 ? `${r.enEspera} en espera` : '',
    ].filter(Boolean);
    return partes.length > 0 ? partes.join(', ') : 'No hay operaciones pendientes.';
  }

  /** Vuelve a leer de IndexedDB cuántas operaciones esperan y cuánto catálogo hay guardado. */
  async refrescarEstado(): Promise<void> {
    if (!this.db.soportado) return;
    try {
      this.pendientes.set(await this.db.contarPendientes(this.auth.currentUser()?.id ?? null));
      const catalogo = await this.db.obtenerCatalogo(this.empresaActual());
      this.variantesOffline.set(catalogo.length);
      this.catalogoDescargadoEn.set(catalogo.reduce<string | null>((max, f) => (max === null || f.sincronizado_en > max ? f.sincronizado_en : max), null));
      this.catalogoVersion.update((v) => v + 1);
    } catch (error) {
      console.error('[OfflineSync] No se pudo leer el estado de la base local', error);
    }
  }

  /** Corre [tarea] sobre [elementos] de [tamano] en [tamano] a la vez (para no saturar el backend). */
  private async enTandas<T, R>(elementos: T[], tamano: number, tarea: (e: T) => Promise<R>): Promise<R[]> {
    const resultados: R[] = [];
    for (let i = 0; i < elementos.length; i += tamano) {
      resultados.push(...(await Promise.all(elementos.slice(i, i + tamano).map(tarea))));
    }
    return resultados;
  }
}
