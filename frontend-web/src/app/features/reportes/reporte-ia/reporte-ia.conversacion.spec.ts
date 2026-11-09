import { signal } from '@angular/core';
import { ComponentFixture, TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { of } from 'rxjs';
import { ResultadoReporte } from '../../../core/models/reporte.model';
import { AuthService } from '../../../core/services/auth.service';
import { CatalogoService } from '../../../core/services/catalogo.service';
import { ReportesService } from '../../../core/services/reportes.service';
import { SucursalesService } from '../../../core/services/sucursales.service';
import { ReporteIa } from './reporte-ia';

/** CU14 — "Los 10 productos más vendidos de los últimos 3 meses agrupados por sucursal" y cómo sigue la charla. */
const porSucursal: ResultadoReporte = {
  estado: 'ok',
  mensaje: null,
  tipo: 'productos_por_sucursal',
  titulo: 'Productos más vendidos por sucursal',
  filtros_aplicados: ['Del 14/08/2026 al 11/11/2026', 'Todas las sucursales', 'Top 10'],
  intencion: { tipo: 'productos_por_sucursal', fecha_inicio: '2026-08-14', fecha_fin: '2026-11-11', limite: 10, descartados: [] },
  columnas: [
    { clave: 'sucursal', titulo: 'Sucursal', tipo: 'texto' },
    { clave: 'etiqueta', titulo: 'Producto', tipo: 'texto' },
    { clave: 'unidades', titulo: 'Unidades', tipo: 'numero' },
  ],
  filas: [
    { sucursal: 'Centro', etiqueta: 'Camisa', unidades: 10 },
    { sucursal: 'Norte', etiqueta: 'Jean', unidades: 7 },
  ],
  totales: { unidades: 17 },
  grafico: 'barras',
  medida: 'unidades',
  grupos: [
    { nombre: 'Centro', puntos: [{ etiqueta: 'Camisa', valor: 10 }] },
    { nombre: 'Norte', puntos: [{ etiqueta: 'Jean', valor: 7 }] },
  ],
  sucursales_sin_datos: ['Equipetrol'],
  resumen: 'En Centro, lo más vendido fue Camisa (10 u.). En Norte, lo más vendido fue Jean (7 u.).',
  sugerencias: ['Solo la sucursal Centro', 'Mostralo en torta'],
  origen: 'ia',
};

describe('ReporteIa — conversación y reportes por sucursal', () => {
  let fixture: ComponentFixture<ReporteIa>;
  let solicitar: ReturnType<typeof vi.fn>;

  beforeEach(async () => {
    solicitar = vi.fn(() => of(porSucursal));
    TestBed.configureTestingModule({
      imports: [ReporteIa],
      providers: [
        provideRouter([]),
        { provide: AuthService, useValue: { isAdmin: signal(true) } },
        {
          provide: ReportesService,
          useValue: {
            catalogo: () => of({ plan_incluye_ia: true, tipos: [], ejemplos: [] }),
            historial: () => of([]),
            solicitar,
          },
        },
        { provide: SucursalesService, useValue: { listar: () => of([]) } },
        { provide: CatalogoService, useValue: { listarCategorias: () => of([]) } },
      ],
    });
    fixture = TestBed.createComponent(ReporteIa);
    await fixture.whenStable();
    fixture.detectChanges();
  });

  const html = () => fixture.nativeElement as HTMLElement;

  it('la primera frase va sin contexto y se dibuja un gráfico por sucursal, más las sin datos', () => {
    fixture.componentInstance.generar('Los 10 productos más vendidos de los últimos 3 meses agrupados por sucursal');
    fixture.detectChanges();

    expect(solicitar).toHaveBeenCalledWith(expect.stringContaining('agrupados por sucursal'), null);
    const grupos = [...html().querySelectorAll('.grupo h3')].map((h) => h.textContent?.trim());
    expect(grupos).toEqual(['Centro', 'Norte', 'Equipetrol']);
    expect(html().querySelectorAll('.grupo app-grafico-reporte').length).toBe(2);
    expect(html().querySelector('.resumen')?.textContent).toContain('En Norte, lo más vendido fue Jean');
  });

  it('la frase siguiente continúa la conversación: viaja con la intención del reporte en pantalla', () => {
    fixture.componentInstance.generar('Los 10 productos más vendidos de los últimos 3 meses agrupados por sucursal');
    fixture.detectChanges();
    html().querySelector<HTMLButtonElement>('.seguir .chip')!.click(); // "Solo la sucursal Centro"
    fixture.detectChanges();

    const [frase, contexto] = solicitar.mock.calls[1];
    expect(frase).toBe('Solo la sucursal Centro');
    expect(contexto).toEqual({ tipo: 'productos_por_sucursal', fecha_inicio: '2026-08-14', fecha_fin: '2026-11-11', limite: 10 });
    const quienes = [...html().querySelectorAll('.conversacion li .quien')].map((q) => q.textContent?.trim());
    expect(quienes).toEqual(['Vos', 'SmartLook IA', 'Vos']); // la última respuesta está en la tarjeta
  });

  it('"Empezar una consulta nueva" corta la conversación', () => {
    fixture.componentInstance.generar('ventas por sucursal');
    fixture.detectChanges();
    fixture.componentInstance.nuevaConsulta();
    fixture.componentInstance.generar('stock bajo');

    expect(solicitar.mock.calls[1][1]).toBeNull();
  });
});
