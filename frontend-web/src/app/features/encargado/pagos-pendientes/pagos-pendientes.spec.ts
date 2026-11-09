import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { ComponentFixture, TestBed } from '@angular/core/testing';
import { environment } from '../../../../environments/environment';
import { Pago } from '../../../core/models/pago.model';
import { ReembolsoDetalle } from '../../../core/models/reserva.model';
import { PagosPendientes } from './pagos-pendientes';

const BASE = `${environment.apiUrl}/pagos`;
const URL_LISTA = `${BASE}/pendientes-verificacion`;
const URL_REEMBOLSOS = `${environment.apiUrl}/devoluciones/reembolsos`;
const URL_PROCESAR = `${URL_REEMBOLSOS}/procesar`;
const URL_QR = 'https://api.test/uploads/qr_devolucion/reembolso_9_abc.png';
const URL_COMPROBANTE = 'https://api.test/uploads/comprobantes/pago_7_abc.png';

const pago = (id: number, estado: Pago['estado'], extra: Partial<Pago> = {}): Pago => ({
  id,
  venta_id: 40 + id,
  metodo: 'qr',
  monto: 200,
  estado,
  referencia_externa: null,
  procesado_en: '2026-11-10T10:00:00Z',
  nombre_venta: `Venta #${40 + id}`,
  monto_formateado: '$200.00',
  comprobante_path: `comprobantes/pago_${id}.png`,
  comprobante_url: id === 7 ? URL_COMPROBANTE : `https://api.test/uploads/comprobantes/pago_${id}.png`,
  ...extra,
});

const reembolso = (id: number, origen: { venta_id: number } | { reserva_id: number }, extra: Partial<ReembolsoDetalle> = {}): ReembolsoDetalle => ({
  id,
  estado: 'pendiente',
  reserva_id: null,
  venta_id: null,
  cliente_id: 3,
  monto: 200,
  tiene_qr: true,
  qr_devolucion_url: URL_QR,
  origen: 'venta_id' in origen ? 'venta' : 'reserva',
  sucursal_id: 1,
  nombre_sucursal: 'Centro',
  nombre_cliente: 'Cliente Uno',
  email_cliente: 'c1@t.bo',
  ...origen,
  ...extra,
});

describe('Pagos por verificar: compra offline del cliente con pago QR y comprobante', () => {
  let fixture: ComponentFixture<PagosPendientes>;
  let page: PagosPendientes;
  let http: HttpTestingController;

  const html = () => fixture.nativeElement as HTMLElement;
  const texto = () => html().textContent ?? '';
  const botones = (raiz: ParentNode = html()) => [...raiz.querySelectorAll('button')] as HTMLButtonElement[];
  const boton = (t: string, raiz: ParentNode = html()) => botones(raiz).find((b) => b.textContent?.trim() === t);
  const tarjeta = (id: number) => [...html().querySelectorAll('article.pago-card')].find((a) => a.textContent?.includes(`Pago #${id}`)) as HTMLElement;

  function abrir(pagos: Pago[], reembolsos: ReembolsoDetalle[] = []) {
    fixture = TestBed.createComponent(PagosPendientes);
    page = fixture.componentInstance;
    http = TestBed.inject(HttpTestingController);
    fixture.detectChanges();
    http.expectOne(URL_LISTA).flush(pagos);
    const pedido = http.expectOne((r) => r.url === URL_REEMBOLSOS);
    expect(pedido.request.params.get('estado')).toBe('pendiente');
    pedido.flush(reembolsos);
    fixture.detectChanges();
  }

  const seccion = () => html().querySelector('[data-testid="reembolsos"]') as HTMLElement;
  const tarjetaReembolso = (id: number) => seccion().querySelector(`[data-reembolso="${id}"]`) as HTMLElement;
  const recargaReembolsos = (datos: ReembolsoDetalle[] = []) => http.expectOne((r) => r.url === URL_REEMBOLSOS).flush(datos);

  function abrirDetalle(id: number) {
    tarjeta(id).click();
    fixture.detectChanges();
  }

  beforeEach(() => {
    TestBed.configureTestingModule({ providers: [provideHttpClient(), provideHttpClientTesting()] });
  });

  afterEach(() => {
    http.verify();
    vi.restoreAllMocks();
  });

  it('las compras offline aparecen con su etiqueta y sus acciones; los pagos QR de siempre no cambian', () => {
    abrir([pago(7, 'pendiente_verificacion'), pago(8, 'pendiente')]);

    expect(tarjeta(7).textContent).toContain('COMPRA OFFLINE');
    expect(boton('Aprobar venta', tarjeta(7))).toBeTruthy();
    expect(boton('Rechazar y reembolsar', tarjeta(7))).toBeTruthy();
    expect(boton('Confirmar pago', tarjeta(7))).toBeUndefined();

    expect(tarjeta(8).textContent).toContain('PENDIENTE');
    expect(tarjeta(8).textContent).not.toContain('COMPRA OFFLINE');
    expect(boton('Confirmar pago', tarjeta(8))).toBeTruthy();
    expect(boton('Rechazar', tarjeta(8))).toBeTruthy();
    expect(boton('Aprobar venta', tarjeta(8))).toBeUndefined();
    expect(texto()).toContain('Pagos por verificar');
  });

  it('el detalle muestra la imagen del comprobante que subió el cliente desde el celular y los dos botones grandes', () => {
    abrir([pago(7, 'pendiente_verificacion')]);
    abrirDetalle(7);

    const modal = html().querySelector('.modal-container') as HTMLElement;
    const img = modal.querySelector('img.modal-comprobante-img') as HTMLImageElement;
    expect(img.getAttribute('src')).toBe(URL_COMPROBANTE);
    expect(modal.textContent).toContain('COMPRA OFFLINE');
    expect((modal.querySelector('[data-testid="aviso-offline"]') as HTMLElement).textContent).toContain('El stock todavía no se descontó');

    const aprobar = boton('Aprobar Venta', modal)!;
    const rechazar = boton('Rechazar y Reembolsar', modal)!;
    expect(aprobar.classList.contains('btn-grande')).toBe(true);
    expect(rechazar.classList.contains('btn-grande')).toBe(true);
    expect(boton('Confirmar pago', modal)).toBeUndefined();
  });

  it('el detalle de un pago QR normal conserva sus botones de siempre', () => {
    abrir([pago(8, 'pendiente')]);
    abrirDetalle(8);

    const modal = html().querySelector('.modal-container') as HTMLElement;
    expect(boton('Confirmar pago', modal)).toBeTruthy();
    expect(boton('Rechazar', modal)).toBeTruthy();
    expect(boton('Aprobar Venta', modal)).toBeUndefined();
    expect(modal.querySelector('[data-testid="aviso-offline"]')).toBeNull();
  });

  it('Aprobar Venta: pide confirmación, llama POST /verificar con APROBAR y recarga la lista', () => {
    const confirmar = vi.spyOn(window, 'confirm').mockReturnValue(true);
    abrir([pago(7, 'pendiente_verificacion')]);
    abrirDetalle(7);

    boton('Aprobar Venta', html().querySelector('.modal-container') as HTMLElement)!.click();

    expect(confirmar.mock.calls[0][0]).toContain('Venta #47');
    expect(confirmar.mock.calls[0][0]).toContain('Se descontará el stock');
    const req = http.expectOne(`${BASE}/7/verificar`);
    expect(req.request.method).toBe('POST');
    expect(req.request.body).toEqual({ accion: 'APROBAR' });
    req.flush({ ...pago(7, 'completado'), venta_estado: 'completada', reembolso_id: null });
    fixture.detectChanges();

    expect(page.modalDetalleAbierto()).toBe(false);
    expect(texto()).toContain('Venta #47 aprobada: stock descontado');
    http.expectOne(URL_LISTA).flush([]); // ya no está pendiente
    fixture.detectChanges();
    expect(texto()).toContain('¡Todo al día!');
  });

  it('Rechazar y Reembolsar: pide el motivo, llama POST /verificar con RECHAZAR y avisa que quedó un reembolso pendiente', () => {
    const preguntar = vi.spyOn(window, 'prompt').mockReturnValue('  comprobante borroso ');
    abrir([pago(7, 'pendiente_verificacion')]);
    abrirDetalle(7);

    boton('Rechazar y Reembolsar', html().querySelector('.modal-container') as HTMLElement)!.click();

    expect(preguntar.mock.calls[0][0]).toContain('reembolso pendiente');
    const req = http.expectOne(`${BASE}/7/verificar`);
    expect(req.request.method).toBe('POST');
    expect(req.request.body).toEqual({ accion: 'RECHAZAR', motivo: 'comprobante borroso' });
    req.flush({ ...pago(7, 'fallido'), venta_estado: 'cancelada', reembolso_id: 3 });
    fixture.detectChanges();

    expect(texto()).toContain('Venta #47 rechazada. Quedó un reembolso pendiente para el cliente');
    expect(page.toastIsError()).toBe(false);
    http.expectOne(URL_LISTA).flush([]);
  });

  it('si el cajero cancela la confirmación o el motivo no se llama al servidor', () => {
    vi.spyOn(window, 'confirm').mockReturnValue(false);
    vi.spyOn(window, 'prompt').mockReturnValue(null);
    abrir([pago(7, 'pendiente_verificacion')]);

    boton('Aprobar venta', tarjeta(7))!.click();
    boton('Rechazar y reembolsar', tarjeta(7))!.click();

    http.expectNone(`${BASE}/7/verificar`);
    expect(page.pagos()).toHaveLength(1);
  });

  it('si al aprobar ya no hay stock muestra el motivo del servidor y recarga la lista (la venta se canceló)', () => {
    vi.spyOn(window, 'confirm').mockReturnValue(true);
    abrir([pago(7, 'pendiente_verificacion')]);

    boton('Aprobar venta', tarjeta(7))!.click();
    http
      .expectOne(`${BASE}/7/verificar`)
      .flush({ detail: 'No hay stock suficiente para esta compra: la venta se canceló y quedó un reembolso pendiente para el cliente' }, { status: 409, statusText: 'Conflict' });
    fixture.detectChanges();

    expect(texto()).toContain('la venta se canceló y quedó un reembolso pendiente');
    expect(page.toastIsError()).toBe(true);
    expect(page.procesando()).toBe(false);
    http.expectOne(URL_LISTA).flush([]);
  });

  it('un pago QR normal se sigue confirmando con PATCH /confirmar-qr (no con /verificar)', () => {
    vi.spyOn(window, 'confirm').mockReturnValue(true);
    abrir([pago(8, 'pendiente')]);

    boton('Confirmar pago', tarjeta(8))!.click();

    http.expectNone(`${BASE}/8/verificar`);
    const req = http.expectOne(`${BASE}/8/confirmar-qr`);
    expect(req.request.method).toBe('PATCH');
    expect(req.request.body).toEqual({ aprobar: true, motivo_rechazo: undefined });
    req.flush(pago(8, 'completado'));
    http.expectOne(URL_LISTA).flush([]);
  });

  // ---------------------------------------------------------------------------------------------------------------
  // Reembolsos pendientes: compras rechazadas (venta_id) y reservas canceladas
  // ---------------------------------------------------------------------------------------------------------------

  it('lista los reembolsos pendientes de COMPRAS (venta_id) y de reservas, con el QR que subió el cliente', () => {
    abrir([], [reembolso(9, { venta_id: 41 }), reembolso(10, { reserva_id: 5 }, { qr_devolucion_url: null, tiene_qr: false, monto: 80 })]);

    expect(seccion().textContent).toContain('Reembolsos pendientes');
    const compra = tarjetaReembolso(9);
    expect(compra.textContent).toContain('Compra #41');
    expect(compra.textContent).toContain('Cliente Uno');
    expect(compra.textContent).toContain('$200.00');
    expect(compra.textContent).toContain('El cliente subió su QR');
    const img = compra.querySelector('img') as HTMLImageElement;
    expect(img.getAttribute('src')).toBe(URL_QR);
    expect(img.getAttribute('alt')).toBe('QR de devolución del cliente');

    const reserva = tarjetaReembolso(10);
    expect(reserva.textContent).toContain('Reserva #5');
    expect(reserva.textContent).toContain('$80.00');
    expect(reserva.textContent).toContain('El cliente aún no subió su QR de devolución');
    expect(reserva.querySelector('img')).toBeNull();
    expect(boton('Procesar Reembolso', compra)).toBeTruthy();
  });

  it('sin reembolsos pendientes lo dice claramente', () => {
    abrir([], []);

    expect(seccion().textContent).toContain('No hay reembolsos pendientes');
  });

  it('Procesar Reembolso de una COMPRA: confirma, llama POST /procesar con venta_id y recarga la lista', () => {
    const confirmar = vi.spyOn(window, 'confirm').mockReturnValue(true);
    abrir([], [reembolso(9, { venta_id: 41 })]);

    boton('Procesar Reembolso', tarjetaReembolso(9))!.click();

    expect(confirmar.mock.calls[0][0]).toContain('transferiste $200.00 al QR del cliente');
    const req = http.expectOne(URL_PROCESAR);
    expect(req.request.method).toBe('POST');
    expect(req.request.body).toEqual({ venta_id: 41 });
    req.flush({ ...reembolso(9, { venta_id: 41 }, { estado: 'reembolsado' }) });
    fixture.detectChanges();

    expect(texto()).toContain('Reembolso de la compra #41 realizado');
    expect(page.toastIsError()).toBe(false);
    recargaReembolsos([]); // ya no está pendiente
    fixture.detectChanges();
    expect(seccion().textContent).toContain('No hay reembolsos pendientes');
  });

  it('Procesar Reembolso de una RESERVA usa reserva_id', () => {
    vi.spyOn(window, 'confirm').mockReturnValue(true);
    abrir([], [reembolso(10, { reserva_id: 5 })]);

    boton('Procesar Reembolso', tarjetaReembolso(10))!.click();

    const req = http.expectOne(URL_PROCESAR);
    expect(req.request.body).toEqual({ reserva_id: 5 });
    req.flush({ ...reembolso(10, { reserva_id: 5 }, { estado: 'reembolsado' }) });
    recargaReembolsos([]);
  });

  it('sin QR del cliente avisa en la confirmación pero se puede procesar igual', () => {
    const confirmar = vi.spyOn(window, 'confirm').mockReturnValue(true);
    abrir([], [reembolso(9, { venta_id: 41 }, { qr_devolucion_url: null, tiene_qr: false })]);

    boton('Procesar Reembolso', tarjetaReembolso(9))!.click();

    expect(confirmar.mock.calls[0][0]).toContain('todavía no subió su QR');
    http.expectOne(URL_PROCESAR).flush({ ...reembolso(9, { venta_id: 41 }, { estado: 'reembolsado' }) });
    recargaReembolsos([]);
  });

  it('si el cajero no confirma no se llama al servidor; si el servidor lo rechaza se muestra el motivo', () => {
    const confirmar = vi.spyOn(window, 'confirm').mockReturnValue(false);
    abrir([], [reembolso(9, { venta_id: 41 })]);

    boton('Procesar Reembolso', tarjetaReembolso(9))!.click();
    http.expectNone(URL_PROCESAR);

    confirmar.mockReturnValue(true);
    boton('Procesar Reembolso', tarjetaReembolso(9))!.click();
    http.expectOne(URL_PROCESAR).flush({ detail: 'Este pedido ya fue reembolsado' }, { status: 409, statusText: 'Conflict' });
    fixture.detectChanges();

    expect(texto()).toContain('Este pedido ya fue reembolsado');
    expect(page.toastIsError()).toBe(true);
    expect(page.procesando()).toBe(false);
    recargaReembolsos([]);
  });

  it('si no se pueden cargar los reembolsos la lista de pagos sigue funcionando', () => {
    fixture = TestBed.createComponent(PagosPendientes);
    page = fixture.componentInstance;
    http = TestBed.inject(HttpTestingController);
    fixture.detectChanges();
    http.expectOne(URL_LISTA).flush([pago(7, 'pendiente_verificacion')]);
    http.expectOne((r) => r.url === URL_REEMBOLSOS).flush({ detail: 'error' }, { status: 500, statusText: 'Server Error' });
    fixture.detectChanges();

    expect(page.pagos()).toHaveLength(1);
    expect(seccion().textContent).toContain('No se pudieron cargar los reembolsos pendientes');
  });
});
