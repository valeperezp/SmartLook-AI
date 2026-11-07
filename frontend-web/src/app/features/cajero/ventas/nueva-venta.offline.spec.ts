import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { signal } from '@angular/core';
import { ComponentFixture, TestBed } from '@angular/core/testing';
import 'fake-indexeddb/auto'; // instala los globals de IndexedDB (indexedDB, IDBRequest...) que usa `idb`
import { IDBFactory } from 'fake-indexeddb';
import { environment } from '../../../../environments/environment';
import { Producto } from '../../../core/models/catalogo.model';
import { ItemCatalogoLocal } from '../../../core/models/offline.model';
import { AuthService } from '../../../core/services/auth.service';
import { OfflineDbService } from '../../../core/services/offline-db.service';
import { OfflineSyncService } from '../../../core/services/offline-sync.service';
import { NuevaVenta } from './nueva-venta';

const URL = environment.apiUrl;

const cajero = { id: 7, nombre: 'Cajero Centro', rol: 'cajero', empresa_id: 1, sucursal_id: 1, sucursal_nombre: 'Sucursal Centro' };

const camiseta = { id: 101, nombre: 'Camiseta básica', precio: 19.99 } as Producto;

function fila(producto: number, sucursal: number, talla: number, stock: number): ItemCatalogoLocal {
  return {
    clave: OfflineDbService.claveCatalogo('1', sucursal, producto, talla, 1),
    empresa: '1',
    sucursal_id: sucursal,
    nombre_sucursal: `Sucursal ${sucursal}`,
    producto_id: producto,
    nombre_producto: producto === 101 ? 'Camiseta básica' : 'Jean slim',
    descripcion: null,
    categoria_id: 1,
    nombre_categoria: 'Ropa',
    talla_id: talla,
    nombre_talla: talla === 2 ? 'M' : 'L',
    color_id: 1,
    nombre_color: 'Negro',
    precio_centavos: producto === 101 ? 1999 : 5999,
    imagen_url: null,
    cantidad_disponible: stock,
    sincronizado_en: '2026-11-06T10:00:00.000Z',
  };
}

describe('TPV del cajero: venta sin conexión', () => {
  let fixture: ComponentFixture<NuevaVenta>;
  let pos: NuevaVenta;
  let http: HttpTestingController;
  let db: OfflineDbService;
  let sync: OfflineSyncService;
  let enLinea = true;

  /** Crea el componente con la red encendida o apagada (el componente y el servicio leen `navigator.onLine`). */
  async function crear(online: boolean) {
    enLinea = online;
    vi.spyOn(navigator, 'onLine', 'get').mockImplementation(() => enLinea);
    fixture = TestBed.createComponent(NuevaVenta);
    pos = fixture.componentInstance;
    http = TestBed.inject(HttpTestingController);
    db = TestBed.inject(OfflineDbService);
    sync = TestBed.inject(OfflineSyncService);
    fixture.detectChanges(); // ngOnInit: pide categorías y productos
  }

  /** Responde (o falla) lo que el componente pide al arrancar. */
  function responderArranque(modo: 'ok' | 'sin-red') {
    for (const req of http.match(() => true)) {
      if (modo === 'ok') req.flush([]);
      else req.error(new ProgressEvent('error'));
    }
  }

  const esperar = async (cond: () => boolean | Promise<boolean>, ms = 3000) => {
    await vi.waitFor(async () => expect(await cond()).toBe(true), { timeout: ms });
  };

  beforeEach(() => {
    vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] }); // sin el envío automático de 3 s ni el toast de 4 s
    (globalThis as { indexedDB: IDBFactory }).indexedDB = new IDBFactory();
    TestBed.configureTestingModule({
      providers: [
        provideHttpClient(),
        provideHttpClientTesting(),
        { provide: AuthService, useValue: { currentUser: signal(cajero), getToken: () => 'token', getEmpresaVisitada: () => null } },
      ],
    });
  });

  afterEach(() => {
    vi.useRealTimers();
    vi.restoreAllMocks();
  });

  it('SIN red: "Cobrar" guarda la venta en IndexedDB, limpia el carrito y avisa; no llama al servidor', async () => {
    await crear(false);
    responderArranque('sin-red');
    pos.carrito.set([{ productoId: 101, nombreProducto: 'Camiseta básica', precio: 19.99, tallaId: 2, nombreTalla: 'M', colorId: 1, nombreColor: 'Negro', cantidad: 2 }]);
    pos.clienteId.set(55);

    pos.cobrar();
    await esperar(async () => (await db.obtenerOperacionesPendientes()).length === 1);

    const [op] = await db.obtenerOperacionesPendientes();
    expect(op).toMatchObject({
      tipo_operacion: 'VENTA_CONTADO',
      estado: 'pendiente',
      sucursal_id: 1,
      cajero_id: 7,
      cliente_id: 55,
      usuario_id: 7,
      total_centavos: 3998,
      items: [{ producto_id: 101, talla_id: 2, color_id: 1, cantidad: 2, precio_unitario_centavos: 1999 }],
    });
    expect(op.uuid).toMatch(/^[0-9a-f-]{36}$/);
    expect(await db.obtenerEntradaCola(op.uuid)).toMatchObject({ estado: 'pendiente', intentos: 0 });
    expect(pos.carrito()).toEqual([]);
    expect(pos.clienteId()).toBeNull();
    expect(pos.toast()).toBe('Venta guardada localmente. Se sincronizará cuando vuelva la conexión');
    expect(pos.toastError()).toBe(false);
    expect(pos.procesando()).toBe(false);
    http.expectNone(`${URL}/ventas`);
    expect(sync.pendientes()).toBe(1);
  });

  it('CON red: flujo normal, POST /ventas al servidor y nada se guarda en IndexedDB', async () => {
    await crear(true);
    responderArranque('ok');
    pos.carrito.set([{ productoId: 101, nombreProducto: 'Camiseta básica', precio: 19.99, tallaId: 2, nombreTalla: 'M', colorId: 1, nombreColor: 'Negro', cantidad: 1 }]);

    pos.cobrar();

    const req = http.expectOne(`${URL}/ventas`);
    expect(req.request.method).toBe('POST');
    expect(req.request.body).toMatchObject({ sucursal_id: 1, items: [{ producto_id: 101, talla_id: 2, color_id: 1, cantidad: 1 }] });
    expect(await db.obtenerOperacionesPendientes()).toEqual([]);
    expect(pos.carrito()).toHaveLength(1); // se limpia cuando el servidor responde, como siempre
  });

  it('sin red y con el carrito vacío no guarda nada y avisa', async () => {
    await crear(false);
    responderArranque('sin-red');

    pos.cobrar();

    expect(pos.toast()).toBe('El carrito está vacío');
    expect(await db.obtenerOperacionesPendientes()).toEqual([]);
  });

  it('si no se puede guardar en el dispositivo, el carrito se conserva y se avisa del error', async () => {
    await crear(false);
    responderArranque('sin-red');
    await esperar(() => pos.toast() !== null); // primero el aviso de "sin catálogo" del arranque, para que no pise al siguiente
    vi.spyOn(sync, 'registrarOperacion').mockRejectedValue(new Error('IndexedDB lleno'));
    pos.carrito.set([{ productoId: 101, nombreProducto: 'Camiseta básica', precio: 19.99, tallaId: 2, nombreTalla: 'M', colorId: 1, nombreColor: 'Negro', cantidad: 1 }]);

    pos.cobrar();
    await esperar(() => pos.toast() === 'IndexedDB lleno');

    expect(pos.toastError()).toBe(true);
    expect(pos.carrito()).toHaveLength(1);
    expect(pos.procesando()).toBe(false);
  });

  it('el banner "Modo Offline" se ve sin red (con el texto que da confianza) y se oculta al volver la conexión', async () => {
    await crear(true);
    responderArranque('ok');
    fixture.detectChanges();
    const texto = () => (fixture.nativeElement as HTMLElement).textContent ?? '';
    expect(texto()).not.toContain('Modo Offline');

    enLinea = false;
    window.dispatchEvent(new Event('offline'));
    fixture.detectChanges();
    expect(texto()).toContain('Modo Offline');
    expect(texto()).toContain('Puedes seguir cobrando');
    expect(texto()).toContain('se enviarán solas cuando vuelva la conexión');
    expect(texto()).toContain('Guardar venta sin conexión'); // el botón también lo dice

    enLinea = true;
    window.dispatchEvent(new Event('online'));
    fixture.detectChanges();
    expect(texto()).not.toContain('Modo Offline');
  });

  it('con una venta guardada, el banner muestra cuántas esperan', async () => {
    await crear(false);
    responderArranque('sin-red');
    pos.carrito.set([{ productoId: 101, nombreProducto: 'Camiseta básica', precio: 19.99, tallaId: 2, nombreTalla: 'M', colorId: 1, nombreColor: 'Negro', cantidad: 1 }]);
    window.dispatchEvent(new Event('offline'));

    pos.cobrar();
    await esperar(() => sync.pendientes() === 1);
    fixture.detectChanges();

    expect((fixture.nativeElement as HTMLElement).textContent).toContain('1 pendiente');
  });

  describe('catálogo guardado', () => {
    it('sin red muestra los productos descargados, solo de la sucursal del cajero', async () => {
      await db_guardar([fila(101, 1, 2, 5), fila(102, 1, 2, 3), fila(103, 99, 2, 9)]);
      await crear(false);
      responderArranque('sin-red');

      await esperar(() => pos.productos().length === 2);

      expect(pos.productos().map((p) => p.id).sort()).toEqual([101, 102]); // el 103 es de otra sucursal
      expect(pos.productos().find((p) => p.id === 101)).toMatchObject({ nombre: 'Camiseta básica', precio: 19.99 });
      expect(pos.categorias()).toEqual([{ id: 1, nombre: 'Ropa', activo: true }]);
      expect(pos.catalogoLocal()).toBe(true);
      expect(pos.toast()).toBeNull();
    });

    it('sin red y sin catálogo guardado explica cómo descargarlo', async () => {
      await crear(false);
      responderArranque('sin-red');

      await esperar(() => pos.toast() !== null);

      expect(pos.toast()).toContain('Descargar catálogo para Offline');
      expect(pos.toastError()).toBe(true);
    });

    it('sin red el selector de variantes usa el stock guardado (solo tallas con stock)', async () => {
      await db_guardar([fila(101, 1, 2, 5), fila(101, 1, 3, 0), fila(101, 99, 2, 7)]);
      await crear(false);
      responderArranque('sin-red');

      pos.abrirSelectorVariante(camiseta);
      await esperar(() => !pos.cargandoVariantes());

      http.expectNone(`${URL}/catalogo/productos/101/disponibilidad`);
      expect(pos.variantesDisponibles()).toHaveLength(1); // la talla L está agotada y la otra fila es de otra sucursal
      expect(pos.variantesDisponibles()[0]).toMatchObject({ talla_id: 2, nombre_talla: 'M', cantidad_disponible: 5 });
      expect(pos.varianteSeleccionada()?.talla_id).toBe(2);
    });

    it('CU8: con el catálogo guardado de hace 2 días el TPV muestra "Información desactualizada"', async () => {
      await db_guardar([{ ...fila(101, 1, 2, 5), sincronizado_en: new Date(Date.now() - 48 * 3_600_000).toISOString() }]);
      await crear(false);
      responderArranque('sin-red');
      await esperar(() => pos.catalogoLocal());
      await sync.refrescarEstado();
      fixture.detectChanges();

      const texto = (fixture.nativeElement as HTMLElement).textContent ?? '';
      expect(texto).toContain('Información desactualizada');
      expect(texto).toContain('La información puede estar desactualizada. Conéctate a internet para actualizar.');
    });

    it('CU8: con un catálogo guardado reciente el TPV no muestra el aviso de desactualizado', async () => {
      await db_guardar([{ ...fila(101, 1, 2, 5), sincronizado_en: new Date().toISOString() }]);
      await crear(false);
      responderArranque('sin-red');
      await esperar(() => pos.catalogoLocal());
      await sync.refrescarEstado();
      fixture.detectChanges();

      expect((fixture.nativeElement as HTMLElement).textContent).not.toContain('Información desactualizada');
    });

    it('CU13: la venta offline descuenta el stock que ofrece el selector y un rechazo del servidor lo devuelve', async () => {
      await db_guardar([fila(101, 1, 2, 5)]);
      await crear(false);
      responderArranque('sin-red');
      const stockEnSelector = async () => {
        pos.abrirSelectorVariante(camiseta);
        await esperar(() => !pos.cargandoVariantes());
        return pos.variantesDisponibles()[0]?.cantidad_disponible;
      };

      expect(await stockEnSelector()).toBe(5);
      pos.carrito.set([{ productoId: 101, nombreProducto: 'Camiseta básica', precio: 19.99, tallaId: 2, nombreTalla: 'M', colorId: 1, nombreColor: 'Negro', cantidad: 2 }]);
      pos.cobrar();
      await esperar(async () => (await db.obtenerOperacionesPendientes()).length === 1);
      expect(await stockEnSelector()).toBe(3); // lo vendido ya no se ofrece

      const [op] = await db.obtenerOperacionesPendientes();
      await db.marcarRechazada(op.uuid, 'Stock insuficiente'); // el servidor no tenía stock
      await sync.refrescarEstado();
      expect(await stockEnSelector()).toBe(5); // vuelve a estar disponible para el cajero
    });

    it('el TPV vuelve a leer el catálogo guardado cuando éste cambia (descuento o devolución por rechazo)', async () => {
      await db_guardar([fila(101, 1, 2, 5)]);
      await crear(false);
      responderArranque('sin-red');
      await esperar(() => pos.productos().length === 1);

      await db_guardar([fila(101, 1, 2, 5), fila(102, 1, 2, 3)]); // el catálogo guardado cambió
      await sync.refrescarEstado(); // avisa del cambio (catalogoVersion)
      fixture.detectChanges(); // corre el efecto que relee el catálogo

      await esperar(() => pos.productos().length === 2);
    });

    it('flujo completo sin red: elegir variante, agregar al carrito y guardar la venta', async () => {
      await db_guardar([fila(101, 1, 2, 5)]);
      await crear(false);
      responderArranque('sin-red');

      pos.abrirSelectorVariante(camiseta);
      await esperar(() => !pos.cargandoVariantes() && pos.varianteSeleccionada() !== null);
      pos.cantidadParaAgregar.set(3);
      pos.agregarAlCarrito();
      expect(pos.totalCarrito()).toBeCloseTo(59.97, 2);

      pos.cobrar();
      await esperar(() => pos.carrito().length === 0); // se limpia cuando la venta ya quedó guardada

      expect((await db.obtenerOperacionesPendientes())[0]).toMatchObject({ total_centavos: 5997, items: [{ producto_id: 101, talla_id: 2, cantidad: 3 }] });
    });
  });

  async function db_guardar(items: ItemCatalogoLocal[]) {
    await TestBed.inject(OfflineDbService).guardarCatalogo(items, '1');
  }
});
