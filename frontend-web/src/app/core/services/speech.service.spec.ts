import { TestBed } from '@angular/core/testing';
import { SpeechService, TranscripcionVoz } from './speech.service';

/** Doble del `SpeechRecognition` del navegador: guarda la instancia para disparar sus eventos a mano. */
class ReconocimientoFalso {
  static instancias: ReconocimientoFalso[] = [];
  lang = '';
  interimResults = false;
  onresult: ((e: any) => void) | null = null;
  onerror: ((e: any) => void) | null = null;
  onend: (() => void) | null = null;
  start = vi.fn();
  stop = vi.fn(() => this.onend?.());
  constructor() {
    ReconocimientoFalso.instancias.push(this);
  }
}

const resultado = (texto: string, final: boolean) => ({ results: [Object.assign([{ transcript: texto }], { isFinal: final })] });

describe('SpeechService', () => {
  const ventana = window as any;

  beforeEach(() => {
    ReconocimientoFalso.instancias = [];
    ventana.webkitSpeechRecognition = ReconocimientoFalso;
    TestBed.configureTestingModule({});
  });

  afterEach(() => {
    delete ventana.webkitSpeechRecognition;
    delete ventana.SpeechRecognition;
  });

  const ultima = () => ReconocimientoFalso.instancias[ReconocimientoFalso.instancias.length - 1];

  it('detecta el soporte del navegador', () => {
    expect(TestBed.inject(SpeechService).soportado).toBe(true);
    delete ventana.webkitSpeechRecognition;
    expect(TestBed.inject(SpeechService).soportado).toBe(false);
  });

  it('no hace nada si el navegador no soporta la API', () => {
    delete ventana.webkitSpeechRecognition;
    const servicio = TestBed.inject(SpeechService);
    servicio.iniciarEscucha();
    expect(servicio.escuchando()).toBe(false);
    expect(ReconocimientoFalso.instancias).toHaveLength(0);
  });

  it('inicia la escucha en es-BO con resultados parciales', () => {
    const servicio = TestBed.inject(SpeechService);
    servicio.iniciarEscucha();
    expect(servicio.escuchando()).toBe(true);
    expect(ultima().lang).toBe('es-BO');
    expect(ultima().interimResults).toBe(true);
    expect(ultima().start).toHaveBeenCalled();
  });

  it('emite el texto en tiempo real, parcial y final', () => {
    const servicio = TestBed.inject(SpeechService);
    const recibidos: TranscripcionVoz[] = [];
    servicio.transcripcion$.subscribe((t) => recibidos.push(t));
    servicio.iniciarEscucha();
    ultima().onresult!(resultado('ventas de sep', false));
    ultima().onresult!(resultado('ventas de septiembre', true));
    expect(recibidos).toEqual([
      { texto: 'ventas de sep', final: false },
      { texto: 'ventas de septiembre', final: true },
    ]);
  });

  it('detenerEscucha cierra el reconocimiento y apaga el estado', () => {
    const servicio = TestBed.inject(SpeechService);
    servicio.iniciarEscucha();
    servicio.detenerEscucha();
    expect(ultima().stop).toHaveBeenCalled();
    expect(servicio.escuchando()).toBe(false);
  });

  it('avisa cuando se deniega el permiso del micrófono', () => {
    const servicio = TestBed.inject(SpeechService);
    servicio.iniciarEscucha();
    ultima().onerror!({ error: 'not-allowed' });
    expect(servicio.escuchando()).toBe(false);
    expect(servicio.error()).toContain('micrófono');
  });

  it('limpia el error al volver a intentar', () => {
    const servicio = TestBed.inject(SpeechService);
    servicio.iniciarEscucha();
    ultima().onerror!({ error: 'no-speech' });
    expect(servicio.error()).not.toBeNull();
    servicio.iniciarEscucha();
    expect(servicio.error()).toBeNull();
  });

  it('si es-BO no está soportado reintenta con es-ES sin mostrar error', () => {
    const servicio = TestBed.inject(SpeechService);
    servicio.iniciarEscucha();
    const primera = ultima();
    primera.onerror!({ error: 'language-not-supported' });
    primera.onend!(); // el navegador cierra la instancia anterior
    expect(ReconocimientoFalso.instancias).toHaveLength(2);
    expect(ultima().lang).toBe('es-ES');
    expect(servicio.error()).toBeNull();
    expect(servicio.escuchando()).toBe(true);
  });
});
