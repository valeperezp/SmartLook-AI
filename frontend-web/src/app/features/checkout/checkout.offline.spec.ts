import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { signal } from '@angular/core';
import { ComponentFixture, TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import 'fake-indexeddb/auto'; // instala los globals de IndexedDB (indexedDB, IDBRequest...) que usa `idb`
import { IDBFactory } from 'fake-indexeddb';
import { environment } from '../../../environments/environment';
import { ItemCarrito } from '../../core/models/carrito.model';
import { ItemCatalogoLocal } from '../../core/models/offline.model';
import { AuthService } from '../../core/services/auth.service';
import { CarritoService } from '../../core/services/carrito.service';
import { OfflineDbService } from '../../core/services/offline-db.service';
import { OfflineSyncService } from '../../core/services/offline-sync.service';
import { Checkout } from './checkout';

const URL = environment.apiUrl;
const cliente = { id: 55, nombre: 'Cliente Demo', rol: 'cliente', empresa_id: 1, sucursal_id: null };

const camiseta: ItemCarrito = {
  productoId: 101,
  nombreProducto: 'Camiseta básica',
  precio: 19.99,
  tallaId: 2,
  nombreTalla: 'M',
  colorId: 1,
  nombreColor: 'Negro',
  cantidad: 2,
};

function fila(sucursal: number, nombre: string): ItemCatalogoLocal {
  return {
    clave: OfflineDbService.claveCatalogo('1', sucursal, 101, 2, 1),
    empresa: '1',
    sucursal_id: sucursal,
    nombre_sucursal: nombre,
    producto_id: 101,
    nombre_producto: 'Camiseta básica',
    descripcion: null,
    categoria_id: 1,
    nombre_categoria: 'Ropa',
    talla_id: 2,
    nombre_talla: 'M',
    color_id: 1,
    nombre_color: 'Negro',
    precio_centavos: 1999,
    imagen_url: null,
    cantidad_disponible: 5,
    sincronizado_en: '2026-11-06T10:00:00.000Z',
  };
}

describe('Checkout del cliente: reserva sin conexión', () => {
  let fixture: ComponentFixture<Checkout>;
  let checkout: Checkout;
  let http: HttpTestingController;
  let db: OfflineDbService;
  let sync: OfflineSyncService;
  let carrito: CarritoService;
  let enLinea = true;
  let rolCliente = true;

  async function crear(online: boolean, sucursalesDelServidor: 'ok' | 'sin-red' = online ? 'ok' : 'sin-red') {
    enLinea = online;
    vi.spyOn(navigator, 'onLine', 'get').mockImplementation(() => enLinea);
    carrito = TestBed.inject(CarritoService);
    carrito.items.set([{ ...camiseta }]);
    fixture = TestBed.createComponent(Checkout);
    checkout = fixture.componentInstance;
    http = TestBed.inject(HttpTestingController);
    db = TestBed.inject(OfflineDbService);
    sync = TestBed.inject(OfflineSyncService);
    fixture.detectChanges(); // ngOnInit: pide las sucursales
    for (const req of http.match(`${URL}/sucursales`)) {
      if (sucursalesDelServidor === 'ok') req.flush([{ id: 1, nombre: 'Centro', direccion: 'Av. 1', ciudad: 'La Paz', activa: true }]);
      else req.error(new ProgressEvent('error'));
    }
    await vi.waitFor(() => expect(checkout.cargandoSucursales()).toBe(false));
  }

  const esperar = (cond: () => boolean | Promise<boolean>, ms = 3000) =>
    vi.waitFor(async () => expect(await cond()).toBe(true), { timeout: ms });

  const textoPantalla = () => (fixture.nativeElement as HTMLElement).textContent ?? '';

  beforeEach(() => {
    vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] }); // sin el envío automático de 3 s
    (globalThis as { indexedDB: IDBFactory }).indexedDB = new IDBFactory();
    localStorage.clear();
    rolCliente = true;
    TestBed.configureTestingModule({
      providers: [
        provideHttpClient(),
        provideHttpClientTesting(),
        provideRouter([]),
        {
          provide: AuthService,
          useValue: {
            currentUser: signal(cliente),
            isCliente: () => rolCliente,
            getToken: () => 'token',
            getEmpresaVisitada: () => null,
          },
        },
      ],
    });
  });

  afterEach(() => {
    vi.useRealTimers();
    vi.restoreAllMocks();
    localStorage.clear();
  });

  it('SIN red: "confirmar" guarda una RESERVA_CLIENTE en IndexedDB, vacía el carrito y avisa; no llama al servidor', async () => {
    await db_guardar([fila(8, 'Sucursal Centro')]);
    await crear(false);
    expect(checkout.sucursalId()).toBe(8); // sucursal del catálogo guardado

    checkout.iniciarPago();
    await esperar(() => checkout.reservaGuardadaOffline());

    const [op] = await db.obtenerOperacionesPendientes();
    expect(op).toMatchObject({
      tipo_operacion: 'RESERVA_CLIENTE',
      estado: 'pendiente',
      sucursal_id: 8,
      cliente_id: 55,
      usuario_id: 55,
      total_centavos: 3998,
      items: [{ producto_id: 101, talla_id: 2, color_id: 1, cantidad: 2, precio_unitario_centavos: 1999 }],
    });
    expect(op.uuid).toMatch(/^[0-9a-f-]{36}$/);
    expect(typeof op.fecha).toBe('string');
    expect(await db.obtenerEntradaCola(op.uuid)).toMatchObject({ estado: 'pendiente', intentos: 0 });
    expect(carrito.estaVacio()).toBe(true);
    expect(checkout.creandoVenta()).toBe(false);
    http.expectNone(`${URL}/ventas/online`);
    http.expectNone(`${URL}/reservas`);
    fixture.detectChanges();
    expect(textoPantalla()).toContain('Reserva guardada localmente. Se confirmará cuando vuelva la conexión');
    expect(sync.pendientes()).toBe(1);
  });

  it('CON red: flujo normal (se crea la orden en el servidor) y nada se guarda en IndexedDB', async () => {
    await crear(true);
    expect(checkout.sucursalId()).toBe(1);

    checkout.iniciarPago();

    const req = http.expectOne(`${URL}/ventas/online`);
    expect(req.request.method).toBe('POST');
    expect(req.request.body).toMatchObject({ sucursal_id: 1, items: [{ producto_id: 101, talla_id: 2, color_id: 1, cantidad: 2 }] });
    expect(await db.obtenerOperacionesPendientes()).toEqual([]);
    expect(carrito.items()).toHaveLength(1); // el carrito se vacía cuando el pago termina, como siempre
    expect(checkout.reservaGuardadaOffline()).toBe(false);
  });

  it('el banner "Modo Offline" se ve en el checkout sin red y el botón dice que se guardará como reserva', async () => {
    await db_guardar([fila(8, 'Sucursal Centro')]);
    await crear(false);
    window.dispatchEvent(new Event('offline'));
    fixture.detectChanges();

    expect(textoPantalla()).toContain('Modo Offline');
    expect(textoPantalla()).toContain('quedará como reserva guardada en este dispositivo');
    expect(textoPantalla()).toContain('Guardar reserva sin conexión');

    enLinea = true;
    window.dispatchEvent(new Event('online'));
    fixture.detectChanges();
    expect(textoPantalla()).not.toContain('Modo Offline');
  });

  it('sin red las sucursales salen del catálogo guardado (sin dirección vacía en pantalla)', async () => {
    await db_guardar([fila(8, 'Sucursal Centro'), fila(9, 'Sucursal Norte')]);
    await crear(false);
    fixture.detectChanges();

    expect(checkout.sucursales().map((s) => s.nombre).sort()).toEqual(['Sucursal Centro', 'Sucursal Norte']);
    expect(checkout.errorCheckout()).toBeNull();
    expect(textoPantalla()).not.toContain('()');
  });

  it('sin red y sin catálogo guardado explica cómo descargarlo y no guarda nada', async () => {
    await crear(false);

    expect(checkout.errorCheckout()).toContain('Descargar catálogo para Offline');
    checkout.iniciarPago(); // sin sucursal no se puede reservar
    expect(checkout.errorCheckout()).toContain('sucursal');
    expect(await db.obtenerOperacionesPendientes()).toEqual([]);
    expect(carrito.items()).toHaveLength(1);
  });

  it('si el usuario no es cliente, no guarda la reserva y conserva el carrito', async () => {
    await db_guardar([fila(8, 'Sucursal Centro')]);
    rolCliente = false;
    await crear(false);

    checkout.iniciarPago();
    await esperar(() => checkout.errorCheckout() !== null);

    expect(checkout.errorCheckout()).toContain('cliente');
    expect(await db.obtenerOperacionesPendientes()).toEqual([]);
    expect(carrito.items()).toHaveLength(1);
  });

  it('si falla el guardado local, el carrito se conserva y se muestra el error', async () => {
    await db_guardar([fila(8, 'Sucursal Centro')]);
    await crear(false);
    vi.spyOn(sync, 'registrarOperacion').mockRejectedValue(new Error('IndexedDB lleno'));

    checkout.iniciarPago();
    await esperar(() => checkout.errorCheckout() === 'IndexedDB lleno');

    expect(carrito.items()).toHaveLength(1);
    expect(checkout.reservaGuardadaOffline()).toBe(false);
    expect(checkout.creandoVenta()).toBe(false);
  });

  async function db_guardar(items: ItemCatalogoLocal[]) {
    await TestBed.inject(OfflineDbService).guardarCatalogo(items, '1');
  }
});
