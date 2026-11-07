import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { ComponentFixture, TestBed } from '@angular/core/testing';
import { environment } from '../../../../environments/environment';
import { ConflictoSync } from '../../../core/models/conflicto-sync.model';
import { ConflictosSyncPage } from './conflictos-sync';

const URL_LISTA = `${environment.apiUrl}/sync/conflictos`;
const URL_RESOLVER = `${URL_LISTA}/7/resolver`;
const URL_STOCK = `${environment.apiUrl}/catalogo/productos/101/disponibilidad`;

const conflicto = (): ConflictoSync => ({
  venta_id: 7,
  uuid: 'abc',
  sucursal_id: 1,
  nombre_sucursal: 'Centro',
  cajero_id: 3,
  nombre_cajero: 'Cajero Centro',
  total: 300,
  creada_en: '2026-11-07T10:00:00Z',
  motivo: 'Stock insuficiente en Camisa Talla M. Disponible: 1, solicitado: 3',
  items: [{ producto_id: 101, nombre_producto: 'Camisa', talla_id: 2, nombre_talla: 'M', color_id: 1, nombre_color: 'Negro', cantidad: 3, precio_unitario: 100 }],
});

/** Disponibilidad del producto 101: la talla M (la pedida) casi agotada y la L con stock. */
const disponibilidad = {
  producto_id: 101,
  disponibilidad: [
    {
      sucursal_id: 1,
      nombre_sucursal: 'Centro',
      items: [
        { talla_id: 2, nombre_talla: 'M', color_id: 1, nombre_color: 'Negro', cantidad_disponible: 1, cantidad_reservada: 0, cantidad_vendida: 0 },
        { talla_id: 3, nombre_talla: 'L', color_id: 1, nombre_color: 'Negro', cantidad_disponible: 8, cantidad_reservada: 0, cantidad_vendida: 0 },
        { talla_id: 4, nombre_talla: 'XL', color_id: 1, nombre_color: 'Negro', cantidad_disponible: 0, cantidad_reservada: 0, cantidad_vendida: 0 },
      ],
    },
    { sucursal_id: 2, nombre_sucursal: 'Norte', items: [{ talla_id: 3, nombre_talla: 'L', color_id: 1, nombre_color: 'Negro', cantidad_disponible: 99, cantidad_reservada: 0, cantidad_vendida: 0 }] },
  ],
};

describe('ConflictosSyncPage (CU13: resolución manual)', () => {
  let fixture: ComponentFixture<ConflictosSyncPage>;
  let page: ConflictosSyncPage;
  let http: HttpTestingController;

  const html = () => fixture.nativeElement as HTMLElement;
  const boton = (texto: string) => [...html().querySelectorAll('button')].find((b) => b.textContent?.trim().startsWith(texto)) as HTMLButtonElement | undefined;
  const pulsar = (texto: string) => {
    const b = boton(texto);
    expect(b, `debía existir el botón "${texto}"`).toBeTruthy();
    b!.click();
    fixture.detectChanges();
  };

  async function abrirConConflicto() {
    fixture = TestBed.createComponent(ConflictosSyncPage);
    page = fixture.componentInstance;
    http = TestBed.inject(HttpTestingController);
    fixture.detectChanges();
    http.expectOne(URL_LISTA).flush([conflicto()]);
    fixture.detectChanges();
  }

  beforeEach(() => {
    TestBed.configureTestingModule({ providers: [provideHttpClient(), provideHttpClientTesting()] });
  });

  afterEach(() => http.verify());

  it('lista las ventas EN CONFLICTO con su motivo y prendas', async () => {
    await abrirConConflicto();

    const texto = html().textContent ?? '';
    expect(texto).toContain('Venta #7');
    expect(texto).toContain('En conflicto');
    expect(texto).toContain('Stock insuficiente en Camisa Talla M');
    expect(texto).toContain('3 × Camisa');
    expect(texto).toContain('Talla M · Negro');
  });

  it('sin conflictos lo dice claramente', async () => {
    fixture = TestBed.createComponent(ConflictosSyncPage);
    http = TestBed.inject(HttpTestingController);
    fixture.detectChanges();
    http.expectOne(URL_LISTA).flush([]);
    fixture.detectChanges();

    expect(html().textContent).toContain('No hay ventas en conflicto');
  });

  it('el modal ofrece las 3 acciones: Anular Venta, Ajustar Variante y Forzar Venta', async () => {
    await abrirConConflicto();
    pulsar('Resolver');

    expect(html().querySelector('[role="dialog"]')).toBeTruthy();
    expect(boton('Anular Venta')).toBeTruthy();
    expect(boton('Ajustar Variante')).toBeTruthy();
    expect(boton('Forzar Venta')).toBeTruthy();
  });

  it('Anular Venta: pide confirmación y llama POST /resolver con ANULAR; luego recarga la lista', async () => {
    await abrirConConflicto();
    pulsar('Resolver');
    pulsar('Anular Venta');
    http.expectNone(URL_RESOLVER); // todavía no: falta confirmar
    expect(html().textContent).toContain('No se descuenta stock');

    pulsar('Sí, anular');
    const req = http.expectOne(URL_RESOLVER);
    expect(req.request.method).toBe('POST');
    expect(req.request.body).toEqual({ accion: 'ANULAR' });
    req.flush({ venta_id: 7, accion: 'ANULAR', estado: 'anulada', total: 300 });
    fixture.detectChanges();

    http.expectOne(URL_LISTA).flush([]); // la lista se vuelve a pedir y ya no está
    fixture.detectChanges();
    expect(page.seleccionado()).toBeNull();
    expect(html().textContent).toContain('Venta #7 anulada');
    expect(html().textContent).toContain('No hay ventas en conflicto');
  });

  it('Forzar Venta: avisa que el stock puede quedar negativo y llama POST /resolver con FORZAR (y la nota)', async () => {
    await abrirConConflicto();
    pulsar('Resolver');
    page.nota = 'el cliente ya se llevó la prenda';
    pulsar('Forzar Venta');
    expect(html().textContent).toContain('aunque el inventario quede en negativo');

    pulsar('Sí, forzar venta');
    const req = http.expectOne(URL_RESOLVER);
    expect(req.request.body).toEqual({ accion: 'FORZAR', motivo: 'el cliente ya se llevó la prenda' });
    req.flush({ venta_id: 7, accion: 'FORZAR', estado: 'completada', total: 300 });
    http.expectOne(URL_LISTA).flush([]);
  });

  it('Ajustar Variante: consulta el stock de la sucursal, solo ofrece variantes con stock y llama POST /resolver con AJUSTAR', async () => {
    await abrirConConflicto();
    pulsar('Resolver');
    pulsar('Ajustar Variante');
    http.expectOne(URL_STOCK).flush(disponibilidad);
    fixture.detectChanges();

    const opciones = [...html().querySelectorAll('select option')].map((o) => o.textContent?.replace(/\s+/g, ' ').trim());
    expect(opciones).toEqual(['Talla M · Negro — 1 disp.', 'Talla L · Negro — 8 disp.']); // sin la XL agotada ni la L de otra sucursal
    expect(page.ajusteValido()).toBe(true); // arranca en la variante original, con la cantidad ajustada al stock (1)
    expect(page.filasAjuste()[0].cantidad).toBe(1);

    page.filasAjuste.update((filas) => filas.map((f) => ({ ...f, seleccion: '3_1', cantidad: 3 }))); // cambia a la talla L
    fixture.detectChanges();
    expect(page.ajusteValido()).toBe(true);

    pulsar('Confirmar ajuste');
    const req = http.expectOne(URL_RESOLVER);
    expect(req.request.body).toEqual({ accion: 'AJUSTAR', items: [{ producto_id: 101, talla_id: 3, color_id: 1, cantidad: 3 }] });
    req.flush({ venta_id: 7, accion: 'AJUSTAR', estado: 'completada', total: 300 });
    http.expectOne(URL_LISTA).flush([]);
  });

  it('Ajustar: no deja confirmar una cantidad mayor al stock de la variante elegida', async () => {
    await abrirConConflicto();
    pulsar('Resolver');
    pulsar('Ajustar Variante');
    http.expectOne(URL_STOCK).flush(disponibilidad);
    fixture.detectChanges();

    page.filasAjuste.update((filas) => filas.map((f) => ({ ...f, seleccion: '3_1', cantidad: 9 }))); // la L solo tiene 8
    fixture.detectChanges();

    expect(page.ajusteValido()).toBe(false);
    expect(boton('Confirmar ajuste')!.disabled).toBe(true);
    http.expectNone(URL_RESOLVER);
  });

  it('si el servidor rechaza la resolución (p. ej. sin stock) muestra el motivo en el modal y la venta sigue en conflicto', async () => {
    await abrirConConflicto();
    pulsar('Resolver');
    pulsar('Ajustar Variante');
    http.expectOne(URL_STOCK).flush(disponibilidad);
    fixture.detectChanges();
    page.filasAjuste.update((filas) => filas.map((f) => ({ ...f, seleccion: '3_1', cantidad: 2 })));
    pulsar('Confirmar ajuste');

    http.expectOne(URL_RESOLVER).flush({ detail: 'Stock insuficiente en Camisa Talla L. Disponible: 1, solicitado: 2' }, { status: 400, statusText: 'Bad Request' });
    fixture.detectChanges();

    expect(page.seleccionado()).not.toBeNull(); // el modal sigue abierto
    expect(html().querySelector('[role="alert"]')?.textContent).toContain('Stock insuficiente en Camisa Talla L');
    expect(page.procesando()).toBe(false);
  });

  it('si otro encargado ya la resolvió (409) avisa y recarga la lista', async () => {
    await abrirConConflicto();
    pulsar('Resolver');
    pulsar('Forzar Venta');
    pulsar('Sí, forzar venta');

    http.expectOne(URL_RESOLVER).flush({ detail: 'Esta venta ya no está en conflicto' }, { status: 409, statusText: 'Conflict' });
    fixture.detectChanges();

    expect(html().textContent).toContain('Esta venta ya no está en conflicto');
    http.expectOne(URL_LISTA).flush([]);
  });
});
