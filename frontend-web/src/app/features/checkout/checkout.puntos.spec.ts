import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { signal } from '@angular/core';
import { ComponentFixture, TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import 'fake-indexeddb/auto'; // instala los globals de IndexedDB (indexedDB, IDBRequest...) que usa `idb`
import { IDBFactory } from 'fake-indexeddb';
import { environment } from '../../../environments/environment';
import { ItemCarrito } from '../../core/models/carrito.model';
import { MisPuntos } from '../../core/models/fidelizacion.model';
import { AuthService } from '../../core/services/auth.service';
import { CarritoService } from '../../core/services/carrito.service';
import { Checkout } from './checkout';

const URL = environment.apiUrl;
const cliente = { id: 55, nombre: 'Cliente Demo', rol: 'cliente', empresa_id: 1, sucursal_id: null };

/** 2 × 19.99 = 39.98 → con 1 punto = 10.00 se pueden canjear como mucho 3 puntos (30.00). */
const camiseta: ItemCarrito = {
  productoId: 101, nombreProducto: 'Camiseta básica', precio: 19.99, tallaId: 2, nombreTalla: 'M', colorId: 1, nombreColor: 'Negro', cantidad: 2,
};

const puntos = (saldo: number, valor = 1000): MisPuntos => ({ cliente_id: 55, saldo, valor_punto_centavos: valor, valor_saldo_centavos: saldo * valor });

describe('Checkout del cliente: canje de puntos (CU17)', () => {
  let fixture: ComponentFixture<Checkout>;
  let checkout: Checkout;
  let http: HttpTestingController;

  /** Crea el checkout; [respuestaPuntos] es lo que contesta GET /clientes/mis-puntos (o 'error'). */
  async function crear(respuestaPuntos: MisPuntos | 'error', online = true) {
    vi.spyOn(navigator, 'onLine', 'get').mockReturnValue(online);
    TestBed.inject(CarritoService).items.set([{ ...camiseta }]);
    fixture = TestBed.createComponent(Checkout);
    checkout = fixture.componentInstance;
    http = TestBed.inject(HttpTestingController);
    fixture.detectChanges();
    for (const req of http.match(`${URL}/sucursales`)) req.flush([{ id: 1, nombre: 'Centro', direccion: 'Av. 1', ciudad: 'La Paz', activa: true }]);
    for (const req of http.match(`${URL}/clientes/mis-puntos`)) {
      if (respuestaPuntos === 'error') req.error(new ProgressEvent('error'));
      else req.flush(respuestaPuntos);
    }
    await vi.waitFor(() => expect(checkout.cargandoSucursales()).toBe(false));
    fixture.detectChanges();
  }

  const html = () => fixture.nativeElement as HTMLElement;
  const casilla = () => html().querySelector<HTMLInputElement>('.puntos-canje input[type="checkbox"]');
  const marcar = (valor: boolean) => {
    casilla()!.checked = valor;
    casilla()!.dispatchEvent(new Event('change'));
    fixture.detectChanges();
  };
  const totalFinal = () => html().querySelector('.final-total .val')?.textContent?.replace(/\s/g, '');

  beforeEach(() => {
    vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] });
    (globalThis as { indexedDB: IDBFactory }).indexedDB = new IDBFactory();
    TestBed.configureTestingModule({
      providers: [
        provideHttpClient(),
        provideHttpClientTesting(),
        provideRouter([]),
        { provide: AuthService, useValue: { currentUser: signal(cliente), isCliente: () => true, getToken: () => 'token', getEmpresaVisitada: () => null } },
      ],
    });
  });

  afterEach(() => {
    vi.useRealTimers();
    vi.restoreAllMocks();
  });

  it('pide el saldo y la regla al backend (no están fijos en la web)', async () => {
    await crear(puntos(5));

    expect(checkout.misPuntos()).toEqual(puntos(5));
  });

  it('con puntos disponibles muestra "Usar mis X puntos (Descuento: $Y)" sin pasarse del total', async () => {
    await crear(puntos(5)); // tiene 5 pero el total (39.98) solo admite 3 puntos de 10.00

    expect(casilla()).toBeTruthy();
    expect(html().querySelector('.puntos-canje')!.textContent).toContain('Usar mis 3 puntos (Descuento: $30.00)');
    expect(checkout.puntosUsables()).toBe(3);
  });

  it('si el cliente tiene pocos puntos ofrece todos los que tiene', async () => {
    await crear(puntos(2));

    expect(html().querySelector('.puntos-canje')!.textContent).toContain('Usar mis 2 puntos (Descuento: $20.00)');
  });

  it('la regla de la empresa manda: con un punto de 2.50 el descuento cambia', async () => {
    await crear(puntos(4, 250));

    expect(html().querySelector('.puntos-canje')!.textContent).toContain('Usar mis 4 puntos (Descuento: $10.00)');
  });

  it('al marcar la casilla el total a pagar baja en tiempo real, y al desmarcarla vuelve', async () => {
    await crear(puntos(5));
    expect(totalFinal()).toBe('$39.98');

    marcar(true);
    expect(checkout.puntosACanjear()).toBe(3);
    expect(checkout.totalAPagar()).toBe(9.98);
    expect(totalFinal()).toBe('$9.98');
    expect(html().querySelector('.descuento-puntos')!.textContent).toContain('-$30.00');

    marcar(false);
    expect(totalFinal()).toBe('$39.98');
    expect(html().querySelector('.descuento-puntos')).toBeNull();
  });

  it('al confirmar con la casilla marcada envía puntos_a_canjear en el JSON de la venta', async () => {
    await crear(puntos(5));
    marcar(true);

    checkout.iniciarPago();
    const req = http.expectOne(`${URL}/ventas/online`);

    expect(req.request.body).toEqual({
      sucursal_id: 1,
      items: [{ producto_id: 101, talla_id: 2, color_id: 1, cantidad: 2 }],
      puntos_a_canjear: 3,
    });
    req.flush({ id: 9, total: 9.98 });
    expect(checkout.montoVenta()).toBe(9.98); // lo que se paga es el total que devolvió el servidor, ya con descuento
  });

  it('sin marcar la casilla NO envía puntos_a_canjear', async () => {
    await crear(puntos(5));

    checkout.iniciarPago();

    const req = http.expectOne(`${URL}/ventas/online`);
    expect('puntos_a_canjear' in req.request.body).toBe(false);
    req.flush({ id: 9, total: 39.98 });
  });

  it('una vez creada la orden la casilla queda bloqueada (los puntos ya se descontaron)', async () => {
    await crear(puntos(5));
    marcar(true);
    checkout.iniciarPago();
    http.expectOne(`${URL}/ventas/online`).flush({ id: 9, total: 9.98 });
    fixture.detectChanges();
    await fixture.whenStable(); // ngModel aplica `disabled` en una microtarea
    fixture.detectChanges();

    expect(casilla()!.disabled).toBe(true);
  });

  it('si el servidor rechaza el canje muestra el motivo y la orden no se crea', async () => {
    await crear(puntos(5));
    marcar(true);

    checkout.iniciarPago();
    http.expectOne(`${URL}/ventas/online`).flush({ detail: 'Puntos insuficientes: tienes 1 y quieres canjear 3' }, { status: 400, statusText: 'Bad Request' });

    expect(checkout.errorCheckout()).toContain('Puntos insuficientes');
    expect(checkout.ventaId()).toBeNull();
  });

  it('sin puntos no hay casilla', async () => {
    await crear(puntos(0));

    expect(casilla()).toBeNull();
  });

  it('si no se puede leer el saldo (error del servidor) no se ofrece el canje', async () => {
    await crear('error');

    expect(checkout.misPuntos()).toBeNull();
    expect(casilla()).toBeNull();
  });

  it('sin conexión no se pide el saldo ni se ofrece el canje', async () => {
    await crear('error', false);

    http.expectNone(`${URL}/clientes/mis-puntos`);
    expect(casilla()).toBeNull();
  });
});
