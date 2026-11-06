import { Injectable } from '@angular/core';
import { DBSchema, IDBPDatabase, openDB } from 'idb';
import {
  EntradaCola,
  ItemCatalogoLocal,
  NuevaOperacionLocal,
  OperacionLocal,
} from '../models/offline.model';

/** Estructura de la base local (IndexedDB). */
interface OfflineSchema extends DBSchema {
  /** Catálogo descargado: producto + talla + color + sucursal, con su stock. Se reemplaza completo en cada descarga. */
  catalogo_local: {
    key: string;
    value: ItemCatalogoLocal;
    indexes: { por_empresa: string; por_producto: number };
  };
  /** Operaciones hechas sin conexión (venta de contado, reserva) con su estado. */
  operaciones_pendientes: {
    key: string;
    value: OperacionLocal;
    indexes: { por_estado: string };
  };
  /** Cola de envío: una entrada por operación, con intentos y último error. */
  sync_queue: {
    key: string;
    value: EntradaCola;
    indexes: { por_estado: string };
  };
}

export const NOMBRE_BD = 'smartlook-web-offline';
export const VERSION_BD = 1;

/**
 * Base de datos local de la web (IndexedDB, con la librería `idb`). Guarda el catálogo para consultarlo sin red y las
 * operaciones hechas sin conexión hasta que `OfflineSyncService` las envíe al backend.
 *
 * Si el navegador no tiene IndexedDB (p. ej. modo privado de algunos navegadores) `soportado` es false y los métodos
 * de lectura devuelven vacío; los de escritura lanzan un error claro.
 */
@Injectable({ providedIn: 'root' })
export class OfflineDbService {
  private dbPromesa: Promise<IDBPDatabase<OfflineSchema>> | null = null;

  get soportado(): boolean {
    return typeof indexedDB !== 'undefined';
  }

  private db(): Promise<IDBPDatabase<OfflineSchema>> {
    if (!this.soportado) throw new Error('Este navegador no permite guardar datos sin conexión (IndexedDB no disponible).');
    this.dbPromesa ??= openDB<OfflineSchema>(NOMBRE_BD, VERSION_BD, {
      upgrade(db) {
        const catalogo = db.createObjectStore('catalogo_local', { keyPath: 'clave' });
        catalogo.createIndex('por_empresa', 'empresa');
        catalogo.createIndex('por_producto', 'producto_id');

        const operaciones = db.createObjectStore('operaciones_pendientes', { keyPath: 'uuid' });
        operaciones.createIndex('por_estado', 'estado');

        const cola = db.createObjectStore('sync_queue', { keyPath: 'id' });
        cola.createIndex('por_estado', 'estado');
      },
    });
    return this.dbPromesa;
  }

  // ---------------------------------------------------------------------------
  // Catálogo
  // ---------------------------------------------------------------------------

  static claveCatalogo(empresa: string, sucursalId: number, productoId: number, tallaId: number | null, colorId: number | null): string {
    return `${empresa}|${sucursalId}|${productoId}|${tallaId ?? 0}|${colorId ?? 0}`;
  }

  /**
   * Reemplaza el catálogo de la tienda [empresa] por [items], en UNA transacción: si algo falla, el catálogo anterior
   * queda intacto. Un lote vacío no hace nada (una respuesta vacía por error no borra el catálogo que sí sirve).
   * Devuelve cuántas variantes quedaron guardadas.
   */
  async guardarCatalogo(items: ItemCatalogoLocal[], empresa: string): Promise<number> {
    if (items.length === 0) return 0;
    const db = await this.db();
    const tx = db.transaction('catalogo_local', 'readwrite');
    const almacen = tx.objectStore('catalogo_local');
    for (const clave of await almacen.index('por_empresa').getAllKeys(empresa)) {
      await almacen.delete(clave);
    }
    for (const item of items) await almacen.put({ ...item, empresa });
    await tx.done;
    return items.length;
  }

  /** Variantes guardadas (de una tienda o de todas). Vacío si nunca se descargó el catálogo. */
  async obtenerCatalogo(empresa?: string): Promise<ItemCatalogoLocal[]> {
    if (!this.soportado) return [];
    const db = await this.db();
    return empresa ? db.getAllFromIndex('catalogo_local', 'por_empresa', empresa) : db.getAll('catalogo_local');
  }

  // ---------------------------------------------------------------------------
  // Operaciones sin conexión
  // ---------------------------------------------------------------------------

  /**
   * Registra una operación hecha sin conexión: la guarda como 'pendiente' junto con su entrada en la cola, en una sola
   * transacción. Devuelve el uuid, que sirve de clave de idempotencia en el backend.
   */
  async guardarOperacionLocal(nueva: NuevaOperacionLocal, usuarioId: number | null = null, uuid: string = crypto.randomUUID()): Promise<string> {
    if (nueva.items.length === 0) throw new Error('La operación no tiene ítems.');
    if (nueva.items.some((i) => !Number.isInteger(i.cantidad) || i.cantidad < 1)) throw new Error('Cantidad inválida en la operación.');
    const ahora = new Date().toISOString();
    const operacion: OperacionLocal = {
      uuid,
      tipo_operacion: nueva.tipo_operacion,
      sucursal_id: nueva.sucursal_id,
      cajero_id: nueva.cajero_id ?? null,
      cliente_id: nueva.cliente_id ?? null,
      usuario_id: usuarioId,
      fecha: ahora,
      total_centavos: nueva.items.reduce((suma, i) => suma + i.precio_unitario_centavos * i.cantidad, 0),
      items: nueva.items,
      estado: 'pendiente',
      id_servidor: null,
      mensaje: null,
    };
    const entrada: EntradaCola = {
      id: uuid,
      tipo_operacion: nueva.tipo_operacion,
      estado: 'pendiente',
      intentos: 0,
      ultimo_error: null,
      fecha_creacion: ahora,
      fecha_ultimo_intento: null,
    };
    const db = await this.db();
    const tx = db.transaction(['operaciones_pendientes', 'sync_queue'], 'readwrite');
    try {
      await tx.objectStore('operaciones_pendientes').add(operacion); // add: un uuid repetido falla en vez de pisar
      await tx.objectStore('sync_queue').add(entrada);
    } catch (error) {
      // Si falla un add la transacción se aborta y `tx.done` se rechaza: se consume para que no quede sin manejar
      await tx.done.catch(() => undefined);
      throw error;
    }
    await tx.done;
    return uuid;
  }

  /** Operaciones que esperan enviarse (estado 'pendiente'), de la más antigua a la más nueva. Con [usuarioId] solo las suyas. */
  async obtenerOperacionesPendientes(usuarioId?: number | null): Promise<OperacionLocal[]> {
    return this.obtenerOperaciones('pendiente', usuarioId);
  }

  /** Todas las operaciones (o solo las de un estado), de la más antigua a la más nueva. */
  async obtenerOperaciones(estado?: OperacionLocal['estado'], usuarioId?: number | null): Promise<OperacionLocal[]> {
    if (!this.soportado) return [];
    const db = await this.db();
    const todas = estado ? await db.getAllFromIndex('operaciones_pendientes', 'por_estado', estado) : await db.getAll('operaciones_pendientes');
    return todas
      .filter((o) => usuarioId === undefined || usuarioId === null || o.usuario_id === usuarioId)
      .sort((a, b) => a.fecha.localeCompare(b.fecha));
  }

  async contarPendientes(usuarioId?: number | null): Promise<number> {
    return (await this.obtenerOperacionesPendientes(usuarioId)).length;
  }

  async obtenerEntradaCola(uuid: string): Promise<EntradaCola | undefined> {
    if (!this.soportado) return undefined;
    return (await this.db()).get('sync_queue', uuid);
  }

  // ---------------------------------------------------------------------------
  // Estados (los usa OfflineSyncService)
  // ---------------------------------------------------------------------------

  /** Marca las entradas como 'en_proceso' y suma un intento a cada una (se cuenta al enviar, como en el móvil). */
  async marcarEnProceso(uuids: string[]): Promise<void> {
    await this.actualizarCola(uuids, (e) => ({
      ...e,
      estado: 'en_proceso',
      intentos: e.intentos + 1,
      fecha_ultimo_intento: new Date().toISOString(),
    }));
  }

  /** Fallo transitorio (sin red, error del servidor, "pendiente"): vuelve a 'pendiente' guardando el motivo. */
  async devolverAPendiente(uuid: string, motivo: string): Promise<void> {
    await this.cerrar(uuid, { cola: 'pendiente', operacion: 'pendiente', motivo, idServidor: null });
  }

  async marcarSincronizada(uuid: string, idServidor: number): Promise<void> {
    await this.cerrar(uuid, { cola: 'sincronizado', operacion: 'sincronizada', motivo: null, idServidor });
  }

  async marcarRechazada(uuid: string, motivo: string): Promise<void> {
    await this.cerrar(uuid, { cola: 'rechazado', operacion: 'rechazada', motivo, idServidor: null });
  }

  /** Lo que quedó 'en_proceso' (la pestaña se cerró en medio de un envío) vuelve a 'pendiente' para reintentarse. */
  async liberarOperacionesEnProceso(): Promise<void> {
    if (!this.soportado) return;
    const db = await this.db();
    const enProceso = await db.getAllFromIndex('sync_queue', 'por_estado', 'en_proceso');
    await this.actualizarCola(enProceso.map((e) => e.id), (e) => ({ ...e, estado: 'pendiente' }));
  }

  private async actualizarCola(uuids: string[], cambio: (e: EntradaCola) => EntradaCola): Promise<void> {
    if (uuids.length === 0) return;
    const db = await this.db();
    const tx = db.transaction('sync_queue', 'readwrite');
    for (const uuid of uuids) {
      const actual = await tx.store.get(uuid);
      if (actual) await tx.store.put(cambio(actual));
    }
    await tx.done;
  }

  /** Cambia la operación y su entrada de cola a la vez (transacción única). */
  private async cerrar(
    uuid: string,
    r: { cola: EntradaCola['estado']; operacion: OperacionLocal['estado']; motivo: string | null; idServidor: number | null },
  ): Promise<void> {
    const db = await this.db();
    const tx = db.transaction(['operaciones_pendientes', 'sync_queue'], 'readwrite');
    const operacion = await tx.objectStore('operaciones_pendientes').get(uuid);
    const entrada = await tx.objectStore('sync_queue').get(uuid);
    if (!operacion || !entrada) {
      await tx.done;
      throw new Error(`La operación ${uuid} no existe en la base local.`);
    }
    await tx.objectStore('operaciones_pendientes').put({ ...operacion, estado: r.operacion, id_servidor: r.idServidor, mensaje: r.motivo });
    await tx.objectStore('sync_queue').put({ ...entrada, estado: r.cola, ultimo_error: r.motivo });
    await tx.done;
  }
}
