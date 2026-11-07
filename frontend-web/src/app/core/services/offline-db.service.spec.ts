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

  it('crea las 4 tablas: catalogo_local, operaciones_pendientes, suscripciones_pendientes y sync_queue', async () => {
    await db.obtenerCatalogo();
    const abierta = await new Promise<IDBDatabase>((resolve, reject) => {
      const r = indexedDB.open('smartlook-web-offline');
      r.onsuccess = () => resolve(r.result);
      r.onerror = () => reject(r.error);
    });
    expect([...abierta.objectStoreNames].sort()).toEqual(['catalogo_local', 'operaciones_pendientes', 'suscripciones_pendientes', 'sync_queue']);
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

  /** CU16: "Avísame cuando llegue" hecho sin conexión se guarda en IndexedDB hasta poder enviarse. */
  describe('suscripciones de stock sin conexión (CU16)', () => {
    const pedido = (cliente = 7, producto = 101) => ({ cliente_id: cliente, producto_id: producto, nombre_producto: 'Camisa', talla_id: null, color_id: null, sucursal_id: null });

    it('guarda la suscripción con su uuid y fecha, y la devuelve ordenada', async () => {
      const a = await db.guardarSuscripcionPendiente(pedido(7, 101), 'u-a');
      await new Promise((r) => setTimeout(r, 5));
      await db.guardarSuscripcionPendiente(pedido(7, 102), 'u-b');

      expect(a).toMatchObject({ uuid: 'u-a', cliente_id: 7, producto_id: 101 });
      expect(a.creada_en).toBeTruthy();
      expect((await db.obtenerSuscripcionesPendientes(7)).map((s) => s.uuid)).toEqual(['u-a', 'u-b']);
    });

    it('pedir dos veces la misma prenda no la duplica', async () => {
      const primera = await db.guardarSuscripcionPendiente(pedido(), 'u-1');
      const segunda = await db.guardarSuscripcionPendiente(pedido(), 'u-2');

      expect(segunda.uuid).toBe(primera.uuid);
      expect(await db.obtenerSuscripcionesPendientes()).toHaveLength(1);
    });

    it('se separan por cliente (el navegador es compartido) y se pueden eliminar una vez enviadas', async () => {
      await db.guardarSuscripcionPendiente(pedido(7, 101), 'u-7');
      await db.guardarSuscripcionPendiente(pedido(8, 101), 'u-8');

      expect((await db.obtenerSuscripcionesPendientes(8)).map((s) => s.uuid)).toEqual(['u-8']);
      await db.eliminarSuscripcionPendiente('u-8');
      expect(await db.obtenerSuscripcionesPendientes(8)).toEqual([]);
      expect(await db.obtenerSuscripcionesPendientes(7)).toHaveLength(1);
    });

    it('actualizar de la versión 1 a la 2 conserva lo ya guardado y crea la tabla nueva', async () => {
      // base v1 tal como la dejó la versión anterior de la web: 3 tablas y una operación pendiente
      await new Promise<void>((ok, ko) => {
        const r = indexedDB.open('smartlook-web-offline', 1);
        r.onupgradeneeded = () => {
          const d = r.result;
          d.createObjectStore('catalogo_local', { keyPath: 'clave' }).createIndex('por_empresa', 'empresa');
          d.createObjectStore('operaciones_pendientes', { keyPath: 'uuid' }).createIndex('por_estado', 'estado');
          d.createObjectStore('sync_queue', { keyPath: 'id' }).createIndex('por_estado', 'estado');
        };
        r.onsuccess = () => {
          const tx = r.result.transaction('operaciones_pendientes', 'readwrite');
          tx.objectStore('operaciones_pendientes').put({ uuid: 'vieja', estado: 'pendiente', tipo_operacion: 'VENTA_CONTADO', sucursal_id: 1, fecha: '2026-11-01T00:00:00Z', items: [] });
          tx.oncomplete = () => {
            r.result.close();
            ok();
          };
          tx.onerror = () => ko(tx.error);
        };
        r.onerror = () => ko(r.error);
      });

      expect((await db.obtenerOperaciones()).map((o) => o.uuid)).toEqual(['vieja']); // abre en v2 sin perder nada
      await db.guardarSuscripcionPendiente(pedido(), 'u-nueva'); // y la tabla nueva ya funciona
      expect(await db.obtenerSuscripcionesPendientes()).toHaveLength(1);
    });
  });

  /** CU13: el stock del catálogo local se descuenta al vender offline y se devuelve si el servidor rechaza la operación. */
  describe('stock local (CU13)', () => {
    /** Catálogo del producto 101 en la sucursal 1, descargado hace un minuto (antes de cualquier operación de la prueba). */
    const catalogoCon = (stock: number) => db.guardarCatalogo([{ ...item('1', 1, 101, stock), sincronizado_en: new Date(Date.now() - 60_000).toISOString() }], '1');
    const stockActual = async () => (await db.obtenerCatalogo('1')).find((f) => f.producto_id === 101)?.cantidad_disponible;

    it('guardar una venta offline resta lo vendido del catálogo local', async () => {
      await catalogoCon(5);
      const uuid = await db.guardarOperacionLocal(venta(2), 1);

      expect(await stockActual()).toBe(3);
      expect((await db.obtenerOperaciones()).find((o) => o.uuid === uuid)?.stock_local_descontado).toBe(true);
    });

    it('si el stock local no alcanza, lanza un error y no guarda la operación ni toca el stock', async () => {
      await catalogoCon(1);
      await expect(db.guardarOperacionLocal(venta(2), 1)).rejects.toThrow('Stock insuficiente');

      expect(await stockActual()).toBe(1);
      expect(await db.obtenerOperaciones()).toEqual([]);
      expect(await db.contarPendientes()).toBe(0);
    });

    it('dos ventas offline no pueden vender la misma prenda dos veces', async () => {
      await catalogoCon(3);
      await db.guardarOperacionLocal(venta(2), 1, 'a');
      await expect(db.guardarOperacionLocal(venta(2), 1, 'b')).rejects.toThrow('Disponible: 1');

      expect(await stockActual()).toBe(1);
      expect((await db.obtenerOperaciones()).map((o) => o.uuid)).toEqual(['a']);
    });

    it('una variante que no está en el catálogo descargado se guarda sin descontar nada', async () => {
      await catalogoCon(5);
      const uuid = await db.guardarOperacionLocal({ ...venta(1), items: [{ producto_id: 999, talla_id: 2, color_id: 1, cantidad: 1, precio_unitario_centavos: 100 }] }, 1);

      expect(await stockActual()).toBe(5);
      expect((await db.obtenerOperaciones()).find((o) => o.uuid === uuid)?.stock_local_descontado).toBe(false);
    });

    it('rechazada: devuelve al catálogo local el stock que había descontado', async () => {
      await catalogoCon(5);
      await db.guardarOperacionLocal(venta(2), 1, 'a');
      expect(await stockActual()).toBe(3);

      await db.marcarRechazada('a', 'Stock insuficiente');

      expect(await stockActual()).toBe(5);
      expect((await db.obtenerOperaciones('rechazada'))[0]).toMatchObject({ uuid: 'a', mensaje: 'Stock insuficiente', stock_local_descontado: false });
      expect((await db.obtenerEntradaCola('a'))?.estado).toBe('rechazado');
    });

    it('rechazar dos veces la misma operación no devuelve el stock dos veces', async () => {
      await catalogoCon(5);
      await db.guardarOperacionLocal(venta(2), 1, 'a');
      await db.marcarRechazada('a', 'x');
      await db.marcarRechazada('a', 'otra vez');

      expect(await stockActual()).toBe(5);
    });

    it('una operación aceptada por el servidor (ok) NO devuelve stock', async () => {
      await catalogoCon(5);
      await db.guardarOperacionLocal(venta(2), 1, 'a');
      await db.marcarSincronizada('a', 10);

      expect(await stockActual()).toBe(3);
    });

    it('una pendiente que vuelve a esperar ("pendiente"/error de red) conserva el descuento', async () => {
      await catalogoCon(5);
      await db.guardarOperacionLocal(venta(2), 1, 'a');
      await db.devolverAPendiente('a', 'sin red');

      expect(await stockActual()).toBe(3);
    });

    it('si el catálogo se volvió a descargar después de la venta, el rechazo NO suma (ya es el stock real del servidor)', async () => {
      await catalogoCon(5);
      await db.guardarOperacionLocal(venta(2), 1, 'a');
      // descarga posterior: el servidor ya dice 3 y esa fila es más nueva que la operación
      await db.guardarCatalogo([{ ...item('1', 1, 101, 3), sincronizado_en: new Date(Date.now() + 5_000).toISOString() }], '1');

      await db.marcarRechazada('a', 'Stock insuficiente');

      expect(await stockActual()).toBe(3);
    });

    it('una reserva rechazada también devuelve su stock', async () => {
      await catalogoCon(5);
      await db.guardarOperacionLocal({ ...venta(2), tipo_operacion: 'RESERVA_CLIENTE', cajero_id: null, cliente_id: 4 }, 4, 'r');
      expect(await stockActual()).toBe(3);

      await db.marcarRechazada('r', 'Stock insuficiente');
      expect(await stockActual()).toBe(5);
    });

    it('una operación guardada antes de existir la marca (sin stock_local_descontado) no suma nada al rechazarse', async () => {
      await catalogoCon(5);
      await db.guardarOperacionLocal(venta(2), 1, 'a');
      // simula una operación de una versión anterior: sin la marca, y su descuento nunca ocurrió
      const abierta = await new Promise<IDBDatabase>((ok, ko) => {
        const r = indexedDB.open('smartlook-web-offline');
        r.onsuccess = () => ok(r.result);
        r.onerror = () => ko(r.error);
      });
      await new Promise<void>((ok, ko) => {
        const tx = abierta.transaction('operaciones_pendientes', 'readwrite');
        const store = tx.objectStore('operaciones_pendientes');
        store.get('a').onsuccess = (e) => {
          const op = (e.target as IDBRequest).result;
          delete op.stock_local_descontado;
          store.put(op);
        };
        tx.oncomplete = () => ok();
        tx.onerror = () => ko(tx.error);
      });
      abierta.close();

      await db.marcarRechazada('a', 'x');
      expect(await stockActual()).toBe(3); // no se inventa stock
    });
  });
});
