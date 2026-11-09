import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { ComponentFixture, TestBed } from '@angular/core/testing';
import { environment } from '../../../../environments/environment';
import { Reembolso, Reserva } from '../../../core/models/reserva.model';
import { EncargadoReservas } from './encargado-reservas';

const URL_LISTA = `${environment.apiUrl}/reservas/mi-sucursal`;
const URL_PROCESAR = `${environment.apiUrl}/devoluciones/reembolsos/procesar`;
const URL_QR = 'https://api.test/uploads/qr_devolucion/reembolso_9_abc.png';

const reembolso = (extra: Partial<Reembolso> = {}): Reembolso => ({
  id: 9,
  estado: 'pendiente',
  reserva_id: 5,
  venta_id: null,
  cliente_id: 3,
  monto: 200,
  tiene_qr: true,
  qr_devolucion_url: URL_QR,
  ...extra,
});

const reserva = (id: number, estado: Reserva['estado'], extra: Partial<Reserva> = {}): Reserva => ({
  id,
  cliente_id: 3,
  sucursal_id: 1,
  estado,
  horario_aproximado: null,
  creada_en: '2026-11-07T10:00:00Z',
  nombre_sucursal: 'Centro',
  nombre_cliente: 'Cliente Uno',
  email_cliente: 'c1@t.bo',
  items: [{ id: 1, producto_id: 101, talla_id: 2, color_id: 1, cantidad: 2, nombre_producto: 'Camisa', nombre_talla: 'M', nombre_color: 'Negro', precio_unitario: 100 }],
  total_items: 1,
  total_unidades: 2,
  total_estimado: 200,
  ...extra,
});

describe('Reservas del encargado: reembolso de una reserva cancelada con el QR del cliente', () => {
  let fixture: ComponentFixture<EncargadoReservas>;
  let page: EncargadoReservas;
  let http: HttpTestingController;

  const html = () => fixture.nativeElement as HTMLElement;
  const texto = () => html().textContent ?? '';
  const fila = (id: number) => [...html().querySelectorAll('tbody tr')].find((tr) => tr.textContent?.includes(`#${id}`)) as HTMLElement | undefined;
  const botonEn = (raiz: ParentNode, t: string) => [...raiz.querySelectorAll('button')].find((b) => b.textContent?.trim().startsWith(t)) as HTMLButtonElement | undefined;
  const botonesReembolso = () => [...html().querySelectorAll('button')].filter((b) => b.textContent?.trim() === 'Procesar Reembolso');

  function abrir(reservas: Reserva[]) {
    fixture = TestBed.createComponent(EncargadoReservas);
    page = fixture.componentInstance;
    http = TestBed.inject(HttpTestingController);
    fixture.detectChanges();
    http.expectOne(URL_LISTA).flush(reservas);
    fixture.detectChanges();
  }

  /** Abre el detalle de la reserva [id] (botón "Ver" de su fila). */
  function verDetalle(id: number) {
    botonEn(fila(id)!, 'Ver')!.click();
    fixture.detectChanges();
  }

  beforeEach(() => {
    TestBed.configureTestingModule({ providers: [provideHttpClient(), provideHttpClientTesting()] });
  });

  afterEach(() => {
    http.verify();
    vi.restoreAllMocks();
  });

  it('solo una reserva CANCELADA ofrece el botón "Procesar Reembolso"', () => {
    abrir([reserva(1, 'pendiente'), reserva(2, 'confirmada'), reserva(3, 'atendida'), reserva(5, 'cancelada', { reembolso: reembolso() }), reserva(6, 'reembolsada')]);

    expect(botonesReembolso()).toHaveLength(1);
    expect(botonEn(fila(5)!, 'Procesar Reembolso')).toBeTruthy();
    for (const id of [1, 2, 3, 6]) expect(botonEn(fila(id)!, 'Procesar Reembolso'), `la reserva #${id} no debe tenerlo`).toBeUndefined();
  });

  it('avisa en la tabla cuando el cliente ya subió su QR', () => {
    abrir([reserva(5, 'cancelada', { reembolso: reembolso() }), reserva(7, 'cancelada', { reembolso: null })]);

    expect(fila(5)!.textContent).toContain('QR recibido');
    expect(fila(7)!.textContent).not.toContain('QR recibido');
  });

  it('el detalle muestra el monto y la imagen del QR que subió el cliente', () => {
    abrir([reserva(5, 'cancelada', { reembolso: reembolso({ monto: 150 }) })]);
    verDetalle(5);

    const caja = html().querySelector('[data-testid="reembolso"]') as HTMLElement;
    expect(caja).toBeTruthy();
    expect(caja.textContent).toContain('Monto a devolver');
    expect(caja.textContent).toContain('$150.00');
    expect(caja.textContent).toContain('El cliente subió su QR');
    const img = caja.querySelector('img') as HTMLImageElement;
    expect(img.getAttribute('src')).toBe(URL_QR);
    expect(img.getAttribute('alt')).toBe('QR de devolución del cliente');
    expect((caja.querySelector('a') as HTMLAnchorElement).getAttribute('href')).toBe(URL_QR);
  });

  it('si el cliente no subió su QR lo dice y no muestra ninguna imagen (usa el total de la reserva como monto)', () => {
    abrir([reserva(5, 'cancelada', { reembolso: null })]);
    verDetalle(5);

    const caja = html().querySelector('[data-testid="reembolso"]') as HTMLElement;
    expect(caja.textContent).toContain('El cliente aún no subió su QR de devolución');
    expect(caja.textContent).toContain('$200.00');
    expect(caja.querySelector('img')).toBeNull();
  });

  it('una reserva pendiente no muestra la sección de reembolso', () => {
    abrir([reserva(1, 'pendiente')]);
    verDetalle(1);

    expect(html().querySelector('[data-testid="reembolso"]')).toBeNull();
  });

  it('Procesar Reembolso: pide confirmación, llama POST con la reserva y la deja como REEMBOLSADA', () => {
    const confirmar = vi.spyOn(window, 'confirm').mockReturnValue(true);
    abrir([reserva(5, 'cancelada', { reembolso: reembolso() })]);

    botonEn(fila(5)!, 'Procesar Reembolso')!.click();

    expect(confirmar).toHaveBeenCalledTimes(1);
    expect(confirmar.mock.calls[0][0]).toContain('transferiste $200.00 al QR del cliente');
    const req = http.expectOne(URL_PROCESAR);
    expect(req.request.method).toBe('POST');
    expect(req.request.body).toEqual({ reserva_id: 5 });
    req.flush({ ...reembolso({ estado: 'reembolsado', procesado_en: '2026-11-09T12:00:00Z' }), origen: 'reserva', nombre_cliente: 'Cliente Uno' });
    fixture.detectChanges();

    expect(page.reservas().find((r) => r.id === 5)?.estado).toBe('reembolsada');
    expect(page.reservas().find((r) => r.id === 5)?.reembolso?.estado).toBe('reembolsado');
    expect(fila(5)!.textContent).toContain('REEMBOLSADA');
    expect(botonesReembolso()).toHaveLength(0); // ya no se puede reembolsar otra vez
    expect(texto()).toContain('Reserva #5 reembolsada');
    expect(texto()).toContain('Reembolsadas (1)');
  });

  it('desde el detalle también se procesa, y el detalle pasa a "Reembolso realizado"', () => {
    vi.spyOn(window, 'confirm').mockReturnValue(true);
    abrir([reserva(5, 'cancelada', { reembolso: reembolso() })]);
    verDetalle(5);

    const pie = html().querySelector('.modal-footer') as HTMLElement;
    botonEn(pie, 'Procesar Reembolso')!.click();
    http.expectOne(URL_PROCESAR).flush({ ...reembolso({ estado: 'reembolsado', procesado_en: '2026-11-09T12:00:00Z' }), origen: 'reserva', nombre_cliente: 'Cliente Uno' });
    fixture.detectChanges();

    expect(page.reservaSeleccionada()?.estado).toBe('reembolsada');
    expect((html().querySelector('[data-testid="reembolso"]') as HTMLElement).textContent).toContain('Reembolso realizado');
    expect(botonEn(html().querySelector('.modal-footer')!, 'Procesar Reembolso')).toBeUndefined();
  });

  it('sin QR del cliente avisa en la confirmación pero se puede procesar igual', () => {
    const confirmar = vi.spyOn(window, 'confirm').mockReturnValue(true);
    abrir([reserva(5, 'cancelada', { reembolso: null })]);

    botonEn(fila(5)!, 'Procesar Reembolso')!.click();

    expect(confirmar.mock.calls[0][0]).toContain('todavía no subió su QR');
    http.expectOne(URL_PROCESAR).flush({ ...reembolso({ estado: 'reembolsado', tiene_qr: false, qr_devolucion_url: null }), origen: 'reserva', nombre_cliente: 'Cliente Uno' });
    fixture.detectChanges();
    expect(page.reservas()[0].estado).toBe('reembolsada');
  });

  it('si el cajero no confirma no se llama al servidor', () => {
    vi.spyOn(window, 'confirm').mockReturnValue(false);
    abrir([reserva(5, 'cancelada', { reembolso: reembolso() })]);

    botonEn(fila(5)!, 'Procesar Reembolso')!.click();

    http.expectNone(URL_PROCESAR);
    expect(page.reservas()[0].estado).toBe('cancelada');
  });

  it('si el servidor lo rechaza, la reserva sigue cancelada y se muestra el motivo', () => {
    vi.spyOn(window, 'confirm').mockReturnValue(true);
    abrir([reserva(5, 'cancelada', { reembolso: reembolso() })]);

    botonEn(fila(5)!, 'Procesar Reembolso')!.click();
    http.expectOne(URL_PROCESAR).flush({ detail: 'Este pedido ya fue reembolsado' }, { status: 409, statusText: 'Conflict' });
    fixture.detectChanges();

    expect(page.reservas()[0].estado).toBe('cancelada');
    expect(page.procesando()).toBe(false);
    expect(texto()).toContain('Este pedido ya fue reembolsado');
    expect(page.toastIsError()).toBe(true);
  });

  it('el filtro "Reembolsadas" muestra solo las reservas ya reembolsadas', () => {
    abrir([reserva(5, 'cancelada', { reembolso: reembolso() }), reserva(6, 'reembolsada'), reserva(1, 'pendiente')]);

    page.filtroEstado.set('reembolsada');
    fixture.detectChanges();

    expect(fila(6)).toBeTruthy();
    expect(fila(5)).toBeUndefined();
    expect(fila(1)).toBeUndefined();
  });
});
