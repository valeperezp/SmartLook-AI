import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { ComponentFixture, TestBed } from '@angular/core/testing';
import { environment } from '../../../environments/environment';
import { VentaDevolvible } from '../../core/models/devolucion.model';
import { DevolucionesPage } from './devoluciones-page';

const BASE = `${environment.apiUrl}/devoluciones`;
const URL_STOCK = `${environment.apiUrl}/catalogo/productos/202/disponibilidad`;

const venta = (extra: Partial<VentaDevolvible> = {}): VentaDevolvible => ({
  venta_id: 7,
  uuid: 'abcd1234-aaaa',
  recibo: 'ABCD1234',
  sucursal_id: 1,
  nombre_sucursal: 'Centro',
  estado: 'completada',
  total: 300,
  creada_en: '2026-11-05T10:00:00Z',
  plazo_dias: 7,
  dias_transcurridos: 2,
  dentro_de_plazo: true,
  items: [
    { producto_id: 101, nombre_producto: 'Camisa', talla_id: 2, nombre_talla: 'M', color_id: 1, nombre_color: 'Negro', cantidad_vendida: 3, cantidad_devuelta: 1, cantidad_devolvible: 2, precio_unitario: 100 },
    { producto_id: 103, nombre_producto: 'Gorra', talla_id: null, nombre_talla: null, color_id: null, nombre_color: null, cantidad_vendida: 1, cantidad_devuelta: 1, cantidad_devolvible: 0, precio_unitario: 40 },
  ],
  ...extra,
});

const respuesta = (extra = {}) => ({ id: 5, uuid: 'web-x', venta_id: 7, tipo: 'devolucion', motivo: null, total_devuelto: 100, total_nuevo: 0, diferencia: -100, items: [], ...extra });

describe('Cambios y devoluciones (CU11)', () => {
  let fixture: ComponentFixture<DevolucionesPage>;
  let page: DevolucionesPage;
  let http: HttpTestingController;

  const html = () => fixture.nativeElement as HTMLElement;
  const texto = () => html().textContent ?? '';
  const boton = (t: string) => [...html().querySelectorAll('button')].find((b) => b.textContent?.trim().startsWith(t)) as HTMLButtonElement | undefined;
  const pulsar = (t: string) => {
    const b = boton(t);
    expect(b, `debía existir el botón "${t}"`).toBeTruthy();
    b!.click();
    fixture.detectChanges();
  };

  async function conVenta(v = venta()) {
    page.busqueda = '7';
    page.buscar();
    http.expectOne((r) => r.url === `${BASE}/buscar`).flush(v);
    fixture.detectChanges();
  }

  beforeEach(() => {
    TestBed.configureTestingModule({ providers: [provideHttpClient(), provideHttpClientTesting()] });
    fixture = TestBed.createComponent(DevolucionesPage);
    page = fixture.componentInstance;
    http = TestBed.inject(HttpTestingController);
    fixture.detectChanges();
  });

  afterEach(() => http.verify());

  it('busca por ticket o UUID y muestra las prendas con lo que se puede devolver', async () => {
    page.busqueda = '  ABCD1234 ';
    page.buscar();
    const req = http.expectOne((r) => r.url === `${BASE}/buscar`);
    expect(req.request.params.get('q')).toBe('ABCD1234');
    req.flush(venta());
    fixture.detectChanges();

    expect(texto()).toContain('Venta #7');
    expect(texto()).toContain('recibo ABCD1234');
    expect(texto()).toContain('Camisa');
    expect(texto()).toContain('Dentro del plazo');
    expect(html().querySelectorAll('tbody tr')).toHaveLength(2);
    expect(html().querySelectorAll('tbody input[type="number"]')).toHaveLength(1); // la gorra ya se devolvió completa
  });

  it('si no encuentra la venta muestra el mensaje del servidor', async () => {
    page.busqueda = 'zzzz';
    page.buscar();
    http.expectOne((r) => r.url === `${BASE}/buscar`).flush({ detail: 'No se encontró ninguna venta con ese ticket o UUID' }, { status: 404, statusText: 'Not Found' });
    fixture.detectChanges();

    expect(html().querySelector('[role="alert"]')?.textContent).toContain('No se encontró ninguna venta');
    expect(page.venta()).toBeNull();
  });

  it('las cantidades no pasan de lo que se puede devolver y calculan el reembolso', async () => {
    await conVenta();
    const camisa = page.venta()!.items[0];

    page.fijarCantidad(camisa, 5); // solo se pueden devolver 2
    expect(page.cantidadDe(camisa)).toBe(2);
    page.fijarCantidad(camisa, -3);
    expect(page.cantidadDe(camisa)).toBe(0);
    page.fijarCantidad(camisa, 1);

    expect(page.totalDevuelto()).toBe(100);
    expect(page.puedeProcesar()).toBe(true);
  });

  it('Solo Devolución: llama POST /devoluciones con tipo "devolucion" y muestra el reembolso', async () => {
    await conVenta();
    page.fijarCantidad(page.venta()!.items[0], 2);
    page.motivo = 'no le gustó';
    fixture.detectChanges();

    pulsar('Procesar Devolución');
    const req = http.expectOne((r) => r.url === BASE && r.method === 'POST');
    expect(req.request.body).toEqual({
      venta_id: 7,
      tipo: 'devolucion',
      items_devueltos: [{ producto_id: 101, talla_id: 2, color_id: 1, cantidad: 2 }],
      items_nuevos: [],
      motivo: 'no le gustó',
    });
    req.flush(respuesta({ total_devuelto: 200, diferencia: -200 }));
    http.expectOne((r) => r.url === `${BASE}/buscar`).flush(venta()); // se refresca la venta
    fixture.detectChanges();

    expect(texto()).toContain('Devolución registrada');
    expect(texto()).toContain('Se devuelve al cliente');
    expect(texto()).toContain('$200.00');
  });

  it('el botón no se habilita sin prendas seleccionadas', async () => {
    await conVenta();
    expect(boton('Procesar Devolución')!.disabled).toBe(true);

    page.fijarCantidad(page.venta()!.items[0], 1);
    fixture.detectChanges();
    expect(boton('Procesar Devolución')!.disabled).toBe(false);
  });

  it('Cambio: pide un producto nuevo del catálogo con stock de la sucursal y llama POST con tipo "cambio"', async () => {
    await conVenta();
    page.fijarCantidad(page.venta()!.items[0], 1);
    pulsar('Cambio');
    http.expectOne((r) => r.url === `${environment.apiUrl}/catalogo/productos` && r.params.get('sucursal_id') === '1').flush([
      { id: 202, nombre: 'Polo', precio: 60, activo: true, categoria_id: 1, categoria: { id: 1, nombre: 'Ropa', activo: true } },
    ]);
    fixture.detectChanges();
    expect(page.procesando()).toBe(false);
    expect(page.puedeProcesar()).toBe(false); // un cambio necesita al menos una prenda nueva

    page.elegirProductoNuevo(202);
    http.expectOne(URL_STOCK).flush({
      producto_id: 202,
      disponibilidad: [
        { sucursal_id: 1, nombre_sucursal: 'Centro', items: [
          { talla_id: 3, nombre_talla: 'L', color_id: 1, nombre_color: 'Negro', cantidad_disponible: 4, cantidad_reservada: 0, cantidad_vendida: 0 },
          { talla_id: 4, nombre_talla: 'XL', color_id: 1, nombre_color: 'Negro', cantidad_disponible: 0, cantidad_reservada: 0, cantidad_vendida: 0 },
        ] },
        { sucursal_id: 2, nombre_sucursal: 'Norte', items: [{ talla_id: 5, nombre_talla: 'S', color_id: 1, nombre_color: 'Negro', cantidad_disponible: 9, cantidad_reservada: 0, cantidad_vendida: 0 }] },
      ],
    });
    fixture.detectChanges();
    expect(page.variantes()).toHaveLength(1); // solo la L de esta sucursal (la XL está agotada y la S es de otra sucursal)

    page.agregarNueva();
    fixture.detectChanges();
    expect(page.totalNuevo()).toBe(60);
    expect(page.diferencia()).toBe(-40); // devuelve 100 y se lleva 60
    expect(texto()).toContain('Se devuelve al cliente');

    pulsar('Procesar Devolución');
    const req = http.expectOne((r) => r.url === BASE && r.method === 'POST');
    expect(req.request.body).toMatchObject({
      tipo: 'cambio',
      items_devueltos: [{ producto_id: 101, talla_id: 2, color_id: 1, cantidad: 1 }],
      items_nuevos: [{ producto_id: 202, talla_id: 3, color_id: 1, cantidad: 1 }],
    });
    req.flush(respuesta({ tipo: 'cambio', total_nuevo: 60, diferencia: -40 }));
    http.expectOne((r) => r.url === `${BASE}/buscar`).flush(venta());
    fixture.detectChanges();
    expect(texto()).toContain('Cambio registrado');
  });

  it('Cambio: no se puede agregar más unidades que el stock', async () => {
    await conVenta();
    pulsar('Cambio');
    http.expectOne((r) => r.url === `${environment.apiUrl}/catalogo/productos`).flush([{ id: 202, nombre: 'Polo', precio: 60, activo: true, categoria_id: 1, categoria: { id: 1, nombre: 'Ropa', activo: true } }]);
    page.elegirProductoNuevo(202);
    http.expectOne(URL_STOCK).flush({ producto_id: 202, disponibilidad: [{ sucursal_id: 1, nombre_sucursal: 'Centro', items: [{ talla_id: 3, nombre_talla: 'L', color_id: 1, nombre_color: 'Negro', cantidad_disponible: 2, cantidad_reservada: 0, cantidad_vendida: 0 }] }] });

    page.cantidadNueva = 3;
    expect(page.puedeAgregarNueva()).toBe(false);
    page.cantidadNueva = 2;
    expect(page.puedeAgregarNueva()).toBe(true);
  });

  it('plazo vencido: el servidor rechaza con 400 y la pantalla muestra el motivo (nada se registra)', async () => {
    await conVenta(venta({ dias_transcurridos: 9, dentro_de_plazo: false }));
    expect(texto()).toContain('Pasaron 9 días');
    expect(texto()).toContain('el servidor decide');
    page.fijarCantidad(page.venta()!.items[0], 1);

    page.procesar();
    http.expectOne((r) => r.url === BASE && r.method === 'POST').flush({ detail: 'El plazo para cambios ha vencido' }, { status: 400, statusText: 'Bad Request' });
    fixture.detectChanges();

    expect(html().querySelector('[role="alert"].error')?.textContent).toContain('El plazo para cambios ha vencido');
    expect(page.resultado()).toBeNull();
    expect(page.procesando()).toBe(false);
  });

  it('error de stock o de cantidades: también se muestra el motivo del servidor', async () => {
    await conVenta();
    page.fijarCantidad(page.venta()!.items[0], 1);

    page.procesar();
    http.expectOne((r) => r.url === BASE && r.method === 'POST').flush({ detail: "De 'Camisa' solo se pueden devolver 0 unidad(es)" }, { status: 400, statusText: 'Bad Request' });
    fixture.detectChanges();

    expect(page.errorProceso()).toContain('solo se pueden devolver 0');
  });

  it('una venta que no está completada avisa que no admite devoluciones', async () => {
    await conVenta(venta({ estado: 'cancelada' }));

    expect(texto()).toContain('solo se pueden devolver ventas completadas');
  });
});
