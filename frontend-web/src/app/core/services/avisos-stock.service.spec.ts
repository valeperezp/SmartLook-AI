import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { signal } from '@angular/core';
import { TestBed } from '@angular/core/testing';
import 'fake-indexeddb/auto'; // instala los globals de IndexedDB (indexedDB, IDBRequest...) que usa `idb`
import { IDBFactory } from 'fake-indexeddb';
import { environment } from '../../../environments/environment';
import { Suscripcion } from '../models/suscripcion.model';
import { AuthService } from './auth.service';
import { AvisosStockService, MENSAJE_LLEGO } from './avisos-stock.service';
import { OfflineDbService } from './offline-db.service';

const BASE = `${environment.apiUrl}/suscripciones`;

const suscripcion = (extra: Partial<Suscripcion> = {}): Suscripcion => ({
  id: 1, uuid: null, producto_id: 101, nombre_producto: 'Camisa', talla_id: null, nombre_talla: null, color_id: null, nombre_color: null,
  sucursal_id: null, nombre_sucursal: null, descripcion: 'Camisa', estado: 'pendiente', fecha: '2026-11-07T10:00:00Z', notificado_en: null, visto: false, ...extra,
});

describe('AvisosStockService (CU16: "Avísame cuando llegue")', () => {
  let avisos: AvisosStockService;
  let http: HttpTestingController;
  let db: OfflineDbService;
  const usuario = signal<{ id: number; rol: string } | null>({ id: 7, rol: 'cliente' });
  let enLinea = true;

  beforeEach(() => {
    vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout', 'setInterval', 'clearInterval'] });
    (globalThis as { indexedDB: IDBFactory }).indexedDB = new IDBFactory();
    usuario.set({ id: 7, rol: 'cliente' });
    enLinea = true;
    vi.spyOn(navigator, 'onLine', 'get').mockImplementation(() => enLinea);
    TestBed.configureTestingModule({
      providers: [
        provideHttpClient(),
        provideHttpClientTesting(),
        { provide: AuthService, useValue: { currentUser: usuario, isCliente: () => usuario()?.rol === 'cliente' } },
      ],
    });
    avisos = TestBed.inject(AvisosStockService);
    http = TestBed.inject(HttpTestingController);
    db = TestBed.inject(OfflineDbService);
  });

  afterEach(() => {
    vi.useRealTimers();
    vi.restoreAllMocks();
  });

  /** Espera a que salga la petición (el servicio lee IndexedDB antes) y la responde. */
  async function responder(url: string, metodo: string, cuerpo: object | null, opciones?: { status: number; statusText: string }) {
    for (let i = 0; i < 100; i++) {
      await Promise.resolve();
      await new Promise<void>((r) => (globalThis as unknown as { setImmediate: (f: () => void) => void }).setImmediate(r));
      const abiertas = http.match((req) => req.url === url && req.method === metodo);
      if (abiertas.length) {
        abiertas[0].flush(cuerpo, opciones);
        return abiertas[0];
      }
    }
    throw new Error(`no salió ${metodo} ${url}`);
  }

  describe('suscribirse', () => {
    it('con red envía POST /suscripciones y confirma "Te avisaremos cuando llegue"', async () => {
      const promesa = avisos.suscribirse({ id: 101, nombre: 'Camisa' });
      const req = await responder(BASE, 'POST', suscripcion());
      const r = await promesa;

      expect(req.request.body).toEqual({ producto_id: 101, talla_id: null, color_id: null, sucursal_id: null });
      expect(r).toEqual({ resultado: 'enviada', mensaje: 'Te avisaremos cuando llegue "Camisa".' });
      expect(avisos.espera(101)).toBe(true);
    });

    it('si ya había stock el servidor responde "notificado" y se avisa de una vez', async () => {
      const promesa = avisos.suscribirse({ id: 101, nombre: 'Camisa' });
      await responder(BASE, 'POST', suscripcion({ estado: 'notificado' }));

      expect((await promesa).resultado).toBe('ya-llego');
    });

    it('SIN internet guarda la suscripción en IndexedDB y no llama al servidor', async () => {
      enLinea = false;

      const r = await avisos.suscribirse({ id: 101, nombre: 'Camisa' });

      expect(r.resultado).toBe('guardada');
      expect(r.mensaje).toContain('se enviará al volver la red');
      http.expectNone(BASE);
      expect(await db.obtenerSuscripcionesPendientes(7)).toHaveLength(1);
      expect(avisos.espera(101)).toBe(true); // ya figura como esperada aunque no haya llegado al servidor
      expect(avisos.pendientesLocales()).toHaveLength(1);
    });

    it('si la red falla en medio del envío (status 0) también se guarda sin perderse', async () => {
      const promesa = avisos.suscribirse({ id: 101, nombre: 'Camisa' });
      await responder(BASE, 'POST', null, { status: 0, statusText: 'Unknown Error' });

      expect((await promesa).resultado).toBe('guardada');
      expect(await db.obtenerSuscripcionesPendientes(7)).toHaveLength(1);
    });

    it('un rechazo del servidor (4xx) se muestra y NO se guarda para reintentar', async () => {
      const promesa = avisos.suscribirse({ id: 101, nombre: 'Camisa' });
      await responder(BASE, 'POST', { detail: 'Producto no encontrado' }, { status: 404, statusText: 'Not Found' });

      expect(await promesa).toEqual({ resultado: 'error', mensaje: 'Producto no encontrado' });
      expect(await db.obtenerSuscripcionesPendientes(7)).toEqual([]);
    });

    it('solo los clientes pueden pedir avisos', async () => {
      usuario.set({ id: 9, rol: 'cajero' });

      expect((await avisos.suscribirse({ id: 101, nombre: 'Camisa' })).resultado).toBe('error');
      http.expectNone(BASE);
    });
  });

  describe('refrescar', () => {
    it('envía lo guardado sin conexión (con su uuid) cuando vuelve la red y lo borra de IndexedDB', async () => {
      await db.guardarSuscripcionPendiente({ cliente_id: 7, producto_id: 101, nombre_producto: 'Camisa', talla_id: 2, color_id: null, sucursal_id: 1 }, 'uuid-offline');

      const promesa = avisos.refrescar();
      const envio = await responder(BASE, 'POST', suscripcion({ uuid: 'uuid-offline' }));
      await responder(`${BASE}/mias`, 'GET', [suscripcion({ uuid: 'uuid-offline' })]);
      await promesa;

      expect(envio.request.body).toEqual({ producto_id: 101, talla_id: 2, color_id: null, sucursal_id: 1, uuid: 'uuid-offline' });
      expect(await db.obtenerSuscripcionesPendientes(7)).toEqual([]);
      expect(avisos.pendientesLocales()).toEqual([]);
    });

    it('si el servidor sigue caído lo guardado se conserva para el próximo intento', async () => {
      await db.guardarSuscripcionPendiente({ cliente_id: 7, producto_id: 101, nombre_producto: 'Camisa', talla_id: null, color_id: null, sucursal_id: null }, 'u1');

      const promesa = avisos.refrescar();
      await responder(BASE, 'POST', null, { status: 503, statusText: 'Service Unavailable' });
      await responder(`${BASE}/mias`, 'GET', null, { status: 503, statusText: 'Service Unavailable' });
      await promesa;

      expect(await db.obtenerSuscripcionesPendientes(7)).toHaveLength(1);
    });

    it('una suscripción que el servidor rechaza (4xx) se descarta: nunca va a funcionar', async () => {
      await db.guardarSuscripcionPendiente({ cliente_id: 7, producto_id: 999, nombre_producto: 'Ya no existe', talla_id: null, color_id: null, sucursal_id: null }, 'u1');

      const promesa = avisos.refrescar();
      await responder(BASE, 'POST', { detail: 'Producto no encontrado' }, { status: 404, statusText: 'Not Found' });
      await responder(`${BASE}/mias`, 'GET', []);
      await promesa;

      expect(await db.obtenerSuscripcionesPendientes(7)).toEqual([]);
    });

    it('si llegó algo nuevo muestra "¡Llegó el producto que esperabas!" y la campana cuenta los avisos sin ver', async () => {
      const promesa = avisos.refrescar();
      await responder(`${BASE}/mias`, 'GET', [suscripcion({ id: 1, estado: 'notificado', notificado_en: '2026-11-07T12:00:00Z' }), suscripcion({ id: 2, estado: 'pendiente' })]);
      await promesa;

      expect(avisos.toast()).toBe(MENSAJE_LLEGO);
      expect(avisos.sinVer()).toBe(1);
      expect(avisos.notificaciones()).toHaveLength(1);
    });

    it('el aviso flotante no se repite para lo que ya se mostró y se cierra solo', async () => {
      const lista = [suscripcion({ id: 1, estado: 'notificado' })];
      let p = avisos.refrescar();
      await responder(`${BASE}/mias`, 'GET', lista);
      await p;
      expect(avisos.toast()).toBe(MENSAJE_LLEGO);

      vi.advanceTimersByTime(10_001); // se cierra solo
      expect(avisos.toast()).toBeNull();

      p = avisos.refrescar();
      await responder(`${BASE}/mias`, 'GET', lista); // mismo aviso, sin ver todavía
      await p;
      expect(avisos.toast()).toBeNull();

      p = avisos.refrescar();
      await responder(`${BASE}/mias`, 'GET', [...lista, suscripcion({ id: 3, estado: 'notificado' })]); // llegó otro
      await p;
      expect(avisos.toast()).toBe(MENSAJE_LLEGO);
    });

    it('un aviso ya visto no vuelve a mostrar el aviso flotante', async () => {
      const p = avisos.refrescar();
      await responder(`${BASE}/mias`, 'GET', [suscripcion({ estado: 'notificado', visto: true })]);
      await p;

      expect(avisos.toast()).toBeNull();
      expect(avisos.sinVer()).toBe(0);
    });

    it('sin conexión no llama al servidor pero sí lee lo guardado', async () => {
      enLinea = false;
      await db.guardarSuscripcionPendiente({ cliente_id: 7, producto_id: 101, nombre_producto: 'Camisa', talla_id: null, color_id: null, sucursal_id: null }, 'u1');

      await avisos.refrescar();

      http.expectNone(`${BASE}/mias`);
      expect(avisos.pendientesLocales()).toHaveLength(1);
    });

    it('si no es cliente se limpia todo y no se consulta nada', async () => {
      usuario.set({ id: 9, rol: 'administrador' });

      await avisos.refrescar();

      http.expectNone(`${BASE}/mias`);
      expect(avisos.mias()).toEqual([]);
    });
  });

  it('marcarVistas pone la campana en 0 y avisa al servidor', async () => {
    const p = avisos.refrescar();
    await responder(`${BASE}/mias`, 'GET', [suscripcion({ estado: 'notificado' })]);
    await p;
    expect(avisos.sinVer()).toBe(1);

    const vistas = avisos.marcarVistas();
    expect(avisos.sinVer()).toBe(0); // al instante, sin esperar al servidor
    await responder(`${BASE}/marcar-vistas`, 'POST', { marcadas: 1 });
    await vistas;

    expect(avisos.notificaciones()).toHaveLength(1); // el aviso sigue en el historial
  });
});
