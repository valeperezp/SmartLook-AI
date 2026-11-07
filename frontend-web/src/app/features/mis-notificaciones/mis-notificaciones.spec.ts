import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { signal } from '@angular/core';
import { ComponentFixture, TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import 'fake-indexeddb/auto'; // instala los globals de IndexedDB (indexedDB, IDBRequest...) que usa `idb`
import { IDBFactory } from 'fake-indexeddb';
import { environment } from '../../../environments/environment';
import { Suscripcion } from '../../core/models/suscripcion.model';
import { AuthService } from '../../core/services/auth.service';
import { AvisosStockService } from '../../core/services/avisos-stock.service';
import { MisNotificaciones } from './mis-notificaciones';

const BASE = `${environment.apiUrl}/suscripciones`;

const s = (extra: Partial<Suscripcion>): Suscripcion => ({
  id: 1, uuid: null, producto_id: 101, nombre_producto: 'Camisa', talla_id: 2, nombre_talla: 'M', color_id: 1, nombre_color: 'Negro',
  sucursal_id: 1, nombre_sucursal: 'Centro', descripcion: 'Camisa · Talla M · Negro', estado: 'pendiente', fecha: '2026-11-07T10:00:00Z',
  notificado_en: null, visto: false, ...extra,
});

describe('Mis notificaciones (CU16)', () => {
  let fixture: ComponentFixture<MisNotificaciones>;
  let http: HttpTestingController;

  const texto = () => (fixture.nativeElement as HTMLElement).textContent ?? '';

  async function abrir(lista: Suscripcion[]) {
    fixture = TestBed.createComponent(MisNotificaciones);
    fixture.detectChanges();
    for (let i = 0; i < 100; i++) {
      await Promise.resolve();
      await new Promise<void>((r) => (globalThis as unknown as { setImmediate: (f: () => void) => void }).setImmediate(r));
      const req = http.match(`${BASE}/mias`)[0];
      if (req) {
        req.flush(lista);
        break;
      }
    }
    // la pantalla marca los avisos como vistos (POST pendiente): no se espera a `whenStable`, solo a que termine de pintar
    for (let i = 0; i < 10; i++) {
      await Promise.resolve();
      await new Promise<void>((r) => (globalThis as unknown as { setImmediate: (f: () => void) => void }).setImmediate(r));
    }
    fixture.detectChanges();
  }

  beforeEach(() => {
    vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout', 'setInterval', 'clearInterval'] });
    (globalThis as { indexedDB: IDBFactory }).indexedDB = new IDBFactory();
    TestBed.configureTestingModule({
      providers: [
        provideHttpClient(),
        provideHttpClientTesting(),
        provideRouter([]),
        { provide: AuthService, useValue: { currentUser: signal({ id: 7, rol: 'cliente' }), isCliente: () => true } },
      ],
    });
    http = TestBed.inject(HttpTestingController);
  });

  afterEach(() => vi.useRealTimers());

  it('muestra las prendas que ya llegaron, marcadas como nuevas, y las que todavía espera', async () => {
    await abrir([s({ id: 1, estado: 'notificado', notificado_en: '2026-11-07T12:00:00Z' }), s({ id: 2, producto_id: 202, descripcion: 'Polo', estado: 'pendiente' })]);

    expect(texto()).toContain('¡Llegó Camisa · Talla M · Negro!');
    expect(texto()).toContain('En Centro');
    expect(texto()).toContain('Nuevo');
    expect(texto()).toContain('Esperando');
    expect(texto()).toContain('Polo');
    http.expectOne(`${BASE}/marcar-vistas`).flush({ marcadas: 1 }); // al abrir la pantalla se marcan como vistas
  });

  it('al abrir la pantalla la campana vuelve a 0', async () => {
    await abrir([s({ id: 1, estado: 'notificado' })]);
    const avisos = TestBed.inject(AvisosStockService);

    expect(avisos.sinVer()).toBe(0);
    http.expectOne(`${BASE}/marcar-vistas`).flush({ marcadas: 1 });
  });

  it('sin avisos lo dice claramente', async () => {
    await abrir([s({ id: 2, estado: 'pendiente' })]);

    expect((fixture.nativeElement as HTMLElement).querySelector('[data-testid="sin-avisos"]')).toBeTruthy();
  });
});
