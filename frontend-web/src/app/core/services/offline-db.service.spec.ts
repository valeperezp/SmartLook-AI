import { TestBed } from '@angular/core/testing';
import 'fake-indexeddb/auto'; // instala los globals de IndexedDB (indexedDB, IDBRequest...) que usa `idb`
import { IDBFactory } from 'fake-indexeddb';
import { ItemCatalogoLocal, NuevaOperacionLocal } from '../models/offline.model';
import { OfflineDbService } from './offline-db.service';

function item(empresa: string, sucursal: number, producto: number, stock = 5): ItemCatalogoLocal {
  return {
    clave: OfflineDbService.claveCatalogo(empresa, sucursal, producto, 2, 1),
    empresa,
    sucursal_id: sucursal,
    nombre_sucursal: `Sucursal ${sucursal}`,
    producto_id: producto,
    nombre_producto: `Prenda ${producto}`,
    descripcion: null,
    categoria_id: 1,
    nombre_categoria: 'Camisas',
    talla_id: 2,
    nombre_talla: 'M',
    color_id: 1,
    nombre_color: 'Negro',
    precio_centavos: 8900,
    imagen_url: null,
    cantidad_disponible: stock,
    sincronizado_en: '2026-11-06T10:00:00.000Z',
  };
}

const venta = (cantidad = 2): NuevaOperacionLocal => ({
  tipo_operacion: 'VENTA_CONTADO',
  sucursal_id: 1,
  cajero_id: 7,
  items: [{ producto_id: 101, talla_id: 2, color_id: 1, cantidad, precio_unitario_centavos: 1999 }],
});

describe('OfflineDbService (IndexedDB)', () => {
  let db: OfflineDbService;

  beforeEach(() => {
    (globalThis as { indexedDB: IDBFactory }).indexedDB = new IDBFactory(); // base limpia en cada prueba
    TestBed.configureTestingModule({});
    db = TestBed.inject(OfflineDbService);
  });

  it('crea las 3 tablas: catalogo_local, operaciones_pendientes y sync_queue', async () => {
    await db.obtenerCatalogo();
    const abierta = await new Promise<IDBDatabase>((resolve, reject) => {
      const r = indexedDB.open('smartlook-web-offline');
      r.onsuccess = () => resolve(r.result);
      r.onerror = () => reject(r.error);
    });
    expect([...abierta.objectStoreNames].sort()).toEqual(['catalogo_local', 'operaciones_pendientes', 'sync_queue']);
    abierta.close();
  });

  describe('catálogo', () => {
    it('guarda y devuelve las variantes', async () => {
      expect(await db.obtenerCatalogo()).toEqual([]);
      expect(await db.guardarCatalogo([item('1', 1, 10), item('1', 2, 10)], '1')).toBe(2);
      expect((await db.obtenerCatalogo('1')).map((i) => i.sucursal_id).sort()).toEqual([1, 2]);
    });

    it('cada descarga REEMPLAZA el catálogo de la tienda (lo que ya no existe se borra)', async () => {
      await db.guardarCatalogo([item('1', 1, 10), item('1', 1, 11)], '1');
      await db.guardarCatalogo([item('1', 1, 12)], '1');
      expect((await db.obtenerCatalogo('1')).map((i) => i.producto_id)).toEqual([12]);
    });

    it('un lote vacío no borra el catálogo que sí sirve', async () => {
      await db.guardarCatalogo([item('1', 1, 10)], '1');
      expect(await db.guardarCatalogo([], '1')).toBe(0);
      expect(await db.obtenerCatalogo('1')).toHaveLength(1);
    });

    it('los catálogos de dos tiendas no se mezclan ni se pisan', async () => {
      await db.guardarCatalogo([item('1', 1, 10)], '1');
      await db.guardarCatalogo([item('5', 8, 23)], '5');
      expect((await db.obtenerCatalogo('1')).map((i) => i.producto_id)).toEqual([10]);
      expect((await db.obtenerCatalogo('5')).map((i) => i.producto_id)).toEqual([23]);
      expect(await db.obtenerCatalogo()).toHaveLength(2);
    });
  });

  describe('operaciones', () => {
    it('guarda la operación como pendiente, con su uuid, total y entrada de cola', async () => {
      const uuid = await db.guardarOperacionLocal(venta(2), 9);

      expect(uuid).toMatch(/^[0-9a-f-]{36}$/);
      const [op] = await db.obtenerOperacionesPendientes();
      expect(op).toMatchObject({ uuid, tipo_operacion: 'VENTA_CONTADO', estado: 'pendiente', usuario_id: 9, total_centavos: 3998, id_servidor: null });
      expect(await db.obtenerEntradaCola(uuid)).toMatchObject({ estado: 'pendiente', intentos: 0, ultimo_error: null });
    });

    it('rechaza operaciones sin ítems o con cantidad inválida', async () => {
      await expect(db.guardarOperacionLocal({ ...venta(), items: [] })).rejects.toThrow('ítems');
      await expect(db.guardarOperacionLocal(venta(0))).rejects.toThrow('Cantidad');
      expect(await db.obtenerOperacionesPendientes()).toEqual([]);
    });

    it('un uuid repetido no pisa la operación original', async () => {
      const uuid = await db.guardarOperacionLocal(venta(2), 1, 'fijo');
      await expect(db.guardarOperacionLocal(venta(5), 1, 'fijo')).rejects.toBeTruthy();
      expect((await db.obtenerOperacionesPendientes()).find((o) => o.uuid === uuid)?.items[0].cantidad).toBe(2);
    });

    it('las pendientes salen de la más antigua a la más nueva y se pueden filtrar por usuario', async () => {
      await db.guardarOperacionLocal(venta(1), 1, 'a');
      await new Promise((r) => setTimeout(r, 5));
      await db.guardarOperacionLocal(venta(1), 2, 'b');
      await new Promise((r) => setTimeout(r, 5));
      await db.guardarOperacionLocal(venta(1), 1, 'c');

      expect((await db.obtenerOperacionesPendientes()).map((o) => o.uuid)).toEqual(['a', 'b', 'c']);
      expect((await db.obtenerOperacionesPendientes(1)).map((o) => o.uuid)).toEqual(['a', 'c']);
      expect(await db.contarPendientes(2)).toBe(1);
    });

    it('marcarEnProceso suma un intento y liberarOperacionesEnProceso las devuelve a pendiente', async () => {
      await db.guardarOperacionLocal(venta(), 1, 'a');
      await db.marcarEnProceso(['a']);
      expect(await db.obtenerEntradaCola('a')).toMatchObject({ estado: 'en_proceso', intentos: 1 });

      await db.liberarOperacionesEnProceso();
      expect(await db.obtenerEntradaCola('a')).toMatchObject({ estado: 'pendiente', intentos: 1 });
    });

    it('sincronizada: guarda el id del servidor y sale de las pendientes', async () => {
      await db.guardarOperacionLocal(venta(), 1, 'a');
      await db.marcarSincronizada('a', 77);

      expect(await db.obtenerOperacionesPendientes()).toEqual([]);
      const [op] = await db.obtenerOperaciones('sincronizada');
      expect(op).toMatchObject({ uuid: 'a', estado: 'sincronizada', id_servidor: 77, mensaje: null });
      expect((await db.obtenerEntradaCola('a'))?.estado).toBe('sincronizado');
    });

    it('rechazada: guarda el motivo y no se vuelve a enviar', async () => {
      await db.guardarOperacionLocal(venta(), 1, 'a');
      await db.marcarRechazada('a', 'Stock insuficiente');

      expect(await db.obtenerOperacionesPendientes()).toEqual([]);
      expect((await db.obtenerOperaciones('rechazada'))[0]).toMatchObject({ estado: 'rechazada', mensaje: 'Stock insuficiente' });
      expect((await db.obtenerEntradaCola('a'))?.ultimo_error).toBe('Stock insuficiente');
    });

    it('devolverAPendiente conserva la operación pendiente con el motivo', async () => {
      await db.guardarOperacionLocal(venta(), 1, 'a');
      await db.marcarEnProceso(['a']);
      await db.devolverAPendiente('a', 'Falta sincronizar la venta original');

      expect((await db.obtenerOperacionesPendientes())[0]).toMatchObject({ estado: 'pendiente', mensaje: 'Falta sincronizar la venta original' });
      expect(await db.obtenerEntradaCola('a')).toMatchObject({ estado: 'pendiente', intentos: 1, ultimo_error: 'Falta sincronizar la venta original' });
    });

    it('cambiar el estado de una operación que no existe falla con un error claro', async () => {
      await expect(db.marcarSincronizada('nada', 1)).rejects.toThrow('no existe');
    });
  });
});
