import { provideHttpClient } from '@angular/common/http';
import { provideHttpClientTesting } from '@angular/common/http/testing';
import { signal } from '@angular/core';
import { ComponentFixture, TestBed } from '@angular/core/testing';
import 'fake-indexeddb/auto'; // instala los globals de IndexedDB (indexedDB, IDBRequest...) que usa `idb`
import { IDBFactory } from 'fake-indexeddb';
import { ItemCatalogoLocal } from '../../models/offline.model';
import { AuthService } from '../../services/auth.service';
import { CatalogoService } from '../../services/catalogo.service';
import { OfflineDbService } from '../../services/offline-db.service';
import { OfflineSyncService } from '../../services/offline-sync.service';
import { CatalogoDesactualizado } from './catalogo-desactualizado';

const DIA = 24 * 3_600_000;

const fila = (descargadoEn: string): ItemCatalogoLocal => ({
  clave: OfflineDbService.claveCatalogo('1', 1, 101, 2, 1), empresa: '1', sucursal_id: 1, nombre_sucursal: 'Centro', producto_id: 101,
  nombre_producto: 'Camisa', descripcion: null, categoria_id: 1, nombre_categoria: 'Camisas', talla_id: 2, nombre_talla: 'M',
  color_id: 1, nombre_color: 'Negro', precio_centavos: 1999, imagen_url: null, cantidad_disponible: 5, sincronizado_en: descargadoEn,
});

describe('CatalogoDesactualizado (aviso de más de 24 h)', () => {
  let fixture: ComponentFixture<CatalogoDesactualizado>;
  let sync: OfflineSyncService;
  let db: OfflineDbService;

  beforeEach(() => {
    vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] }); // sin el envío automático de 3 s
    (globalThis as { indexedDB: IDBFactory }).indexedDB = new IDBFactory();
    TestBed.configureTestingModule({
      providers: [
        provideHttpClient(),
        provideHttpClientTesting(),
        { provide: AuthService, useValue: { currentUser: signal({ id: 7, empresa_id: 1 }), getToken: () => 't', getEmpresaVisitada: () => null } },
        { provide: CatalogoService, useValue: {} },
      ],
    });
    fixture = TestBed.createComponent(CatalogoDesactualizado);
    sync = TestBed.inject(OfflineSyncService);
    db = TestBed.inject(OfflineDbService);
  });

  afterEach(() => vi.useRealTimers());

  const texto = () => (fixture.nativeElement as HTMLElement).textContent ?? '';

  it('con el catálogo de hace 2 días muestra "Información desactualizada" con el aviso y la antigüedad', async () => {
    await db.guardarCatalogo([fila(new Date(Date.now() - 2 * DIA - 3_600_000).toISOString())], '1');
    await sync.refrescarEstado();
    fixture.detectChanges();

    expect(texto()).toContain('Información desactualizada');
    expect(texto()).toContain('La información puede estar desactualizada. Conéctate a internet para actualizar.');
    expect(texto()).toContain('hace 2 días');
    expect((fixture.nativeElement as HTMLElement).querySelector('[role="status"]')).toBeTruthy();
  });

  it('con un catálogo reciente no muestra nada', async () => {
    await db.guardarCatalogo([fila(new Date(Date.now() - 2 * 3_600_000).toISOString())], '1');
    await sync.refrescarEstado();
    fixture.detectChanges();

    expect(texto().trim()).toBe('');
  });

  it('el aviso desaparece cuando se actualiza el catálogo', async () => {
    await db.guardarCatalogo([fila(new Date(Date.now() - 3 * DIA).toISOString())], '1');
    await sync.refrescarEstado();
    fixture.detectChanges();
    expect(texto()).toContain('Información desactualizada');

    await db.guardarCatalogo([fila(new Date().toISOString())], '1'); // nueva descarga
    await sync.refrescarEstado();
    fixture.detectChanges();

    expect(texto().trim()).toBe('');
  });
});
