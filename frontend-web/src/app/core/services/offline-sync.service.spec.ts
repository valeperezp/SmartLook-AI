import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { signal } from '@angular/core';
import { TestBed } from '@angular/core/testing';
import 'fake-indexeddb/auto'; // instala los globals de IndexedDB (indexedDB, IDBRequest...) que usa `idb`
import { IDBFactory } from 'fake-indexeddb';
import { of } from 'rxjs';
import { environment } from '../../../environments/environment';
import { Producto, ProductoDisponibilidad } from '../models/catalogo.model';
import { NuevaOperacionLocal } from '../models/offline.model';
import { AuthService } from './auth.service';
import { CatalogoService } from './catalogo.service';
import { OfflineDbService } from './offline-db.service';
import { OfflineSyncService } from './offline-sync.service';

/** Existe en Node (donde corren las pruebas); `fake-indexeddb` también lo usa. Los timers falsos de `vi` no lo tocan. */
declare const setImmediate: (callback: () => void) => unknown;

const URL_SYNC = `${environment.apiUrl}/sync/operaciones`;

const venta = (): NuevaOperacionLocal => ({
  tipo_operacion: 'VENTA_CONTADO',
  sucursal_id: 1,
  cajero_id: 7,
  items: [{ producto_id: 101, talla_id: 2, color_id: 1, cantidad: 2, precio_unitario_centavos: 1999 }],
});

const producto = (id: number, precio = 89): Producto =>
  ({ id, nombre: `Prenda ${id}`, precio, categoria_id: 1, categoria: { id: 1, nombre: 'Camisas', activo: true }, activo: true, imagen_url: undefined }) as Producto;

const disponibilidad = (id: number): ProductoDisponibilidad => ({
  producto_id: id,
  nombre_producto: `Prenda ${id}`,
  precio: 89,
  imagen_url: null,
  total_global: 5,
  sucursales_con_stock: 1,
  disponibilidad: [
    {
      sucursal_id: 1,
      nombre_sucursal: 'Centro',
      ciudad: null,
      total_disponible: 5,
      estado: 'disponible',
      total_reservada: 0,
      total_vendida: 0,
      items: [
        { talla_id: 2, nombre_talla: 'M', color_id: 1, nombre_color: 'Negro', cantidad_disponible: 5, cantidad_reservada: 0, cantidad_vendida: 0 },
        { talla_id: 3, nombre_talla: 'L', color_id: 1, nombre_color: 'Negro', cantidad_disponible: 0, cantidad_reservada: 0, cantidad_vendida: 0 },
      ],
    },
  ],
});

describe('OfflineSyncService', () => {
  let sync: OfflineSyncService;
  let db: OfflineDbService;
  let http: HttpTestingController;
  const usuario = signal<{ id: number; empresa_id: number } | null>({ id: 7, empresa_id: 1 });
  let token: string | null;

  const iniciar = (online = true) => {
    vi.spyOn(navigator, 'onLine', 'get').mockReturnValue(online);
    sync = TestBed.inject(OfflineSyncService);
    db = TestBed.inject(OfflineDbService);
    http = TestBed.inject(HttpTestingController);
  };

  beforeEach(() => {
    vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] }); // evita el envío automático de 3 s al crear el servicio
    (globalThis as { indexedDB: IDBFactory }).indexedDB = new IDBFactory();
    usuario.set({ id: 7, empresa_id: 1 });
    token = 'token-de-prueba';
    TestBed.configureTestingModule({
      providers: [
        provideHttpClient(),
        provideHttpClientTesting(),
        { provide: AuthService, useValue: { currentUser: usuario, getToken: () => token, getEmpresaVisitada: () => null } },
        {
          provide: CatalogoService,
          useValue: {
            listarProductos: () => of([producto(10), producto(11)]),
            obtenerDisponibilidad: (id: number) => of(disponibilidad(id)),
          },
        },
      ],
    });
  });

  afterEach(() => {
    vi.useRealTimers();
    vi.restoreAllMocks();
  });

  /** Como `sincronizarPendientes()` es asíncrona (IndexedDB), se espera a que salga la petición HTTP antes de responderla. */
  async function enviar(responder: (req: ReturnType<HttpTestingController['expectOne']>) => void) {
    const promesa = sync.sincronizarPendientes();
    let req: ReturnType<HttpTestingController['expectOne']> | undefined;
    for (let i = 0; i < 100 && !req; i++) {
      await Promise.resolve();
      await new Promise<void>((r) => setImmediate(r));
      const abiertas = http.match(URL_SYNC);
      if (abiertas.length) req = abiertas[0];
    }
    expect(req, 'debía salir un POST a /sync/operaciones').toBeTruthy();
    responder(req!);
    return promesa;
  }

  it('envía POST /sync/operaciones con el mismo JSON que el móvil y marca "sincronizada" con el id del servidor', async () => {
    iniciar();
    const uuid = await sync.registrarOperacion(venta());
    let cuerpo: any;

    const r = await enviar((req) => {
      expect(req.request.method).toBe('POST');
      cuerpo = req.request.body;
      req.flush({ resultados: [{ uuid, status: 'ok', id_servidor: 42, entidad: 'venta' }] });
    });

    expect(r).toMatchObject({ sincronizadas: 1, rechazadas: 0, fallidas: 0, enEspera: 0 });
    expect(Object.keys(cuerpo).sort()).toEqual(['enviado_en', 'operaciones']);
    expect(cuerpo.operaciones[0]).toMatchObject({
      uuid,
      tipo_operacion: 'VENTA_CONTADO',
      sucursal_id: 1,
      cajero_id: 7,
      cliente_id: null,
      total_centavos: 3998,
      items: [{ producto_id: 101, talla_id: 2, color_id: 1, cantidad: 2, precio_unitario_centavos: 1999 }],
    });
    expect(typeof cuerpo.operaciones[0].fecha).toBe('string');
    const [op] = await db.obtenerOperaciones('sincronizada');
    expect(op).toMatchObject({ uuid, id_servidor: 42 });
    expect(sync.pendientes()).toBe(0);
    expect(sync.ultimoMensaje()).toBe('1 sincronizada');
  });

  it('"conflict": la operación queda rechazada con el motivo del servidor', async () => {
    iniciar();
    const uuid = await sync.registrarOperacion(venta());

    const r = await enviar((req) => req.flush({ resultados: [{ uuid, status: 'conflict', message: 'Stock insuficiente' }] }));

    expect(r.rechazadas).toBe(1);
    expect((await db.obtenerOperaciones('rechazada'))[0]).toMatchObject({ uuid, mensaje: 'Stock insuficiente' });
    expect(await db.obtenerOperacionesPendientes()).toEqual([]);
  });

  it('CU13: un "conflict" por falta de stock en el servidor devuelve el stock local y avisa a las pantallas (catalogoVersion)', async () => {
    iniciar();
    const hace1Min = new Date(Date.now() - 60_000).toISOString();
    await db.guardarCatalogo(
      [{
        clave: OfflineDbService.claveCatalogo('1', 1, 101, 2, 1), empresa: '1', sucursal_id: 1, nombre_sucursal: 'Centro', producto_id: 101,
        nombre_producto: 'Camisa', descripcion: null, categoria_id: 1, nombre_categoria: 'Camisas', talla_id: 2, nombre_talla: 'M',
        color_id: 1, nombre_color: 'Negro', precio_centavos: 1999, imagen_url: null, cantidad_disponible: 5, sincronizado_en: hace1Min,
      }],
      '1',
    );
    const stock = async () => (await db.obtenerCatalogo('1'))[0].cantidad_disponible;

    const uuid = await sync.registrarOperacion(venta()); // vende 2 offline
    expect(await stock()).toBe(3);
    const versionAntes = sync.catalogoVersion();

    const r = await enviar((req) => req.flush({ resultados: [{ uuid, status: 'conflict', message: 'Stock insuficiente' }] }));

    expect(r.rechazadas).toBe(1);
    expect(await stock()).toBe(5); // el stock vuelve a estar disponible para el cajero
    expect(sync.catalogoVersion()).toBeGreaterThan(versionAntes);
  });

  it('"pendiente": sigue pendiente con el mensaje del servidor (ni error ni rechazo) y suma un intento', async () => {
    iniciar();
    const uuid = await sync.registrarOperacion(venta());

    const r = await enviar((req) => req.flush({ resultados: [{ uuid, status: 'pendiente', message: 'Falta sincronizar la venta original' }] }));

    expect(r).toMatchObject({ enEspera: 1, fallidas: 0, rechazadas: 0, sincronizadas: 0 });
    expect(sync.ultimoMensaje()).toBe('1 en espera');
    expect((await db.obtenerOperacionesPendientes())[0]).toMatchObject({ uuid, estado: 'pendiente', mensaje: 'Falta sincronizar la venta original' });
    expect(await db.obtenerEntradaCola(uuid)).toMatchObject({ estado: 'pendiente', intentos: 1 });
  });

  it('en un lote mixto cada operación recibe su resultado', async () => {
    iniciar();
    const a = await sync.registrarOperacion(venta());
    const b = await sync.registrarOperacion(venta());
    const c = await sync.registrarOperacion(venta());

    const r = await enviar((req) =>
      req.flush({
        resultados: [
          { uuid: a, status: 'ok', id_servidor: 1 },
          { uuid: b, status: 'conflict', message: 'x' },
          { uuid: c, status: 'pendiente' },
        ],
      }),
    );

    expect([r.sincronizadas, r.rechazadas, r.enEspera, r.fallidas]).toEqual([1, 1, 1, 0]);
  });

  it.each([
    ['500 del servidor', (req: any) => req.flush({ detail: 'boom' }, { status: 500, statusText: 'Server Error' }), /500/],
    ['404 (el endpoint aún no existe)', (req: any) => req.flush('no', { status: 404, statusText: 'Not Found' }), /404/],
    ['sin red (status 0)', (req: any) => req.error(new ProgressEvent('error')), /sin conexión/i],
  ])('%s: la operación sigue pendiente para reintentarse', async (_nombre, fallar, motivo) => {
    iniciar();
    const uuid = await sync.registrarOperacion(venta());

    const r = await enviar(fallar);

    expect(r.fallidas).toBe(1);
    expect(r.sesionExpirada).toBe(false);
    const [op] = await db.obtenerOperacionesPendientes();
    expect(op.uuid).toBe(uuid);
    expect(op.mensaje).toMatch(motivo);
    expect((await db.obtenerEntradaCola(uuid))?.intentos).toBe(1);
  });

  it('401 (token vencido): NO se pierde nada, queda pendiente y avisa de sesión expirada', async () => {
    iniciar();
    await sync.registrarOperacion(venta());
    await sync.registrarOperacion(venta());

    const r = await enviar((req) => req.flush({ detail: 'x' }, { status: 401, statusText: 'Unauthorized' }));

    expect(r.sesionExpirada).toBe(true);
    expect(r.sincronizadas).toBe(0);
    expect(sync.ultimoMensaje()).toContain('Sesión expirada');
    expect(await db.obtenerOperacionesPendientes()).toHaveLength(2);
  });

  it('una respuesta con "ok" sin id_servidor no se da por buena: sigue pendiente', async () => {
    iniciar();
    const uuid = await sync.registrarOperacion(venta());

    const r = await enviar((req) => req.flush({ resultados: [{ uuid, status: 'ok' }] }));

    expect(r.fallidas).toBe(1);
    expect(await db.obtenerOperacionesPendientes()).toHaveLength(1);
  });

  it('sin red (navigator.onLine = false) no envía nada', async () => {
    iniciar(false);
    await sync.registrarOperacion(venta());

    const r = await sync.sincronizarPendientes();

    expect(r.sinRed).toBe(true);
    expect(sync.ultimoMensaje()).toContain('Sin conexión');
    http.expectNone(URL_SYNC);
    expect(await db.obtenerOperacionesPendientes()).toHaveLength(1);
  });

  it('sin sesión no envía y avisa; las operaciones se conservan', async () => {
    iniciar();
    await sync.registrarOperacion(venta());
    usuario.set(null);
    token = null;

    const r = await sync.sincronizarPendientes();

    expect(r.sesionExpirada).toBe(true);
    http.expectNone(URL_SYNC);
    expect(await db.obtenerOperacionesPendientes()).toHaveLength(1);
  });

  it('solo envía las operaciones del usuario con sesión (no las de otro usuario del mismo navegador)', async () => {
    iniciar();
    const mia = await sync.registrarOperacion(venta());
    await db.guardarOperacionLocal(venta(), 99, 'de-otro-usuario');
    let enviadas: string[] = [];

    await enviar((req) => {
      enviadas = req.request.body.operaciones.map((o: { uuid: string }) => o.uuid);
      req.flush({ resultados: [{ uuid: mia, status: 'ok', id_servidor: 1 }] });
    });

    expect(enviadas).toEqual([mia]);
    expect((await db.obtenerOperacionesPendientes()).map((o) => o.uuid)).toEqual(['de-otro-usuario']);
  });

  it('sin operaciones pendientes no hace ninguna petición', async () => {
    iniciar();
    const r = await sync.sincronizarPendientes();
    expect(r.sincronizadas).toBe(0);
    expect(sync.ultimoMensaje()).toBe('No hay operaciones pendientes.');
    http.expectNone(URL_SYNC);
  });

  it('al volver la conexión (evento "online") sincroniza tras la espera de 3 s', async () => {
    iniciar(false);
    const uuid = await sync.registrarOperacion(venta());
    expect(sync.online()).toBe(false);

    vi.spyOn(navigator, 'onLine', 'get').mockReturnValue(true);
    window.dispatchEvent(new Event('online'));
    expect(sync.online()).toBe(true);
    http.expectNone(URL_SYNC); // todavía dentro de la espera

    await vi.advanceTimersByTimeAsync(3000);
    let req: ReturnType<HttpTestingController['expectOne']> | undefined;
    for (let i = 0; i < 100 && !req; i++) {
      await new Promise<void>((r) => setImmediate(r));
      req = http.match(URL_SYNC)[0];
    }
    expect(req, 'tras 3 s debía enviarse').toBeTruthy();
    req!.flush({ resultados: [{ uuid, status: 'ok', id_servidor: 5 }] });
    await vi.waitFor(async () => expect(await db.obtenerOperacionesPendientes()).toEqual([]));
  });

  it('un parpadeo de la red (online → offline) cancela el envío programado', async () => {
    iniciar(false);
    await sync.registrarOperacion(venta());
    window.dispatchEvent(new Event('online'));
    window.dispatchEvent(new Event('offline'));

    await vi.advanceTimersByTimeAsync(5000);
    http.expectNone(URL_SYNC);
    expect(sync.online()).toBe(false);
  });

  describe('catálogo', () => {
    it('descargarCatalogo guarda una fila por sucursal + producto + talla + color (con y sin stock)', async () => {
      iniciar();

      expect(await sync.descargarCatalogo()).toBe(4); // 2 productos × 2 variantes
      const filas = await db.obtenerCatalogo('1');
      expect(filas).toHaveLength(4);
      expect(filas.find((f) => f.producto_id === 10 && f.talla_id === 2)).toMatchObject({ nombre_sucursal: 'Centro', precio_centavos: 8900, cantidad_disponible: 5, nombre_categoria: 'Camisas' });
      expect(filas.filter((f) => f.cantidad_disponible === 0)).toHaveLength(2);
      expect(sync.variantesOffline()).toBe(4);
      expect(sync.catalogoDescargadoEn()).toBeTruthy();
    });

    it('sin conexión no descarga y avisa', async () => {
      iniciar(false);
      await expect(sync.descargarCatalogo()).rejects.toThrow('Sin conexión');
    });

    it('leerCatalogoLocal arma productos, categorías y sucursales para mostrar el catálogo sin red', async () => {
      iniciar();
      expect(await sync.leerCatalogoLocal()).toBeNull(); // nunca se descargó
      await sync.descargarCatalogo();

      const local = (await sync.leerCatalogoLocal())!;
      expect(local.productos.map((p) => p.id).sort()).toEqual([10, 11]);
      expect(local.productos[0]).toMatchObject({ precio: 89, total_disponible: 5, sucursales_con_stock: 1, estado_global: 'bajo' });
      expect(local.categorias).toEqual([{ id: 1, nombre: 'Camisas', activo: true }]);
      expect(local.sucursales).toEqual([expect.objectContaining({ id: 1, nombre: 'Centro' })]);
    });
  });
});
