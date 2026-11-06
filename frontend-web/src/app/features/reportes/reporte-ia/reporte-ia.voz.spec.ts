import { signal } from '@angular/core';
import { ComponentFixture, TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { of } from 'rxjs';
import { AuthService } from '../../../core/services/auth.service';
import { CatalogoService } from '../../../core/services/catalogo.service';
import { ReportesService } from '../../../core/services/reportes.service';
import { SucursalesService } from '../../../core/services/sucursales.service';
import { ReporteIa } from './reporte-ia';

class ReconocimientoFalso {
  static ultima: ReconocimientoFalso;
  lang = '';
  interimResults = false;
  onresult: ((e: any) => void) | null = null;
  onerror: ((e: any) => void) | null = null;
  onend: (() => void) | null = null;
  start = vi.fn();
  stop = vi.fn(() => this.onend?.());
  constructor() {
    ReconocimientoFalso.ultima = this;
  }
}

describe('ReporteIa — dictado por voz', () => {
  const ventana = window as any;
  let fixture: ComponentFixture<ReporteIa>;

  async function montar(conSoporte: boolean) {
    if (conSoporte) ventana.webkitSpeechRecognition = ReconocimientoFalso;
    else delete ventana.webkitSpeechRecognition;

    TestBed.configureTestingModule({
      imports: [ReporteIa],
      providers: [
        provideRouter([]),
        { provide: AuthService, useValue: { isAdmin: signal(true) } },
        {
          provide: ReportesService,
          useValue: { catalogo: () => of({ plan_incluye_ia: true, tipos: [], ejemplos: [] }), historial: () => of([]) },
        },
        { provide: SucursalesService, useValue: { listar: () => of([]) } },
        { provide: CatalogoService, useValue: { listarCategorias: () => of([]) } },
      ],
    });
    fixture = TestBed.createComponent(ReporteIa);
    await fixture.whenStable();
    fixture.detectChanges();
  }

  afterEach(() => delete ventana.webkitSpeechRecognition);

  const html = () => fixture.nativeElement as HTMLElement;
  const boton = () => html().querySelector<HTMLButtonElement>('button.btn-icono');
  const entrada = () => html().querySelector<HTMLInputElement>('#solicitud')!;

  it('oculta el micrófono si el navegador no soporta la API', async () => {
    await montar(false);
    expect(boton()).toBeNull();
  });

  it('al pulsar el micrófono pasa a "grabando" y muestra "Escuchando..."', async () => {
    await montar(true);
    boton()!.click();
    fixture.detectChanges();
    expect(boton()!.classList).toContain('grabando');
    expect(html().querySelector('.escuchando')!.textContent).toContain('Escuchando...');
  });

  it('coloca el texto dictado en el input de la solicitud', async () => {
    await montar(true);
    boton()!.click();
    ReconocimientoFalso.ultima.onresult!({ results: [Object.assign([{ transcript: 'ventas de septiembre' }], { isFinal: true })] });
    ReconocimientoFalso.ultima.onend!();
    fixture.detectChanges();
    await fixture.whenStable();
    expect(fixture.componentInstance.solicitud).toBe('ventas de septiembre');
    expect(entrada().value).toBe('ventas de septiembre');
  });

  it('muestra una alerta si se deniega el permiso del micrófono', async () => {
    await montar(true);
    boton()!.click();
    ReconocimientoFalso.ultima.onerror!({ error: 'not-allowed' });
    fixture.detectChanges();
    const alerta = html().querySelector('.aviso-voz[role="alert"]');
    expect(alerta?.textContent).toContain('micrófono');
    expect(boton()!.classList).not.toContain('grabando');
  });
});
