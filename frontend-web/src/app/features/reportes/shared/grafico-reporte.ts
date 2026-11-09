import { Component, Input, computed, signal } from '@angular/core';
import { DecimalPipe } from '@angular/common';
import { Grafico } from '../../../core/models/reporte.model';

interface Punto {
  etiqueta: string;
  valor: number;
}

/* Paleta categórica (orden fijo, validada para daltonismo) solo para la torta: cada porción es
   una entidad distinta. Barras y líneas muestran una sola medida y usan un solo tono. */
const PALETA_CLARO = ['#2a78d6', '#eb6834', '#1baf7a', '#eda100', '#e87ba4', '#008300'];
const PALETA_OSCURO = ['#3987e5', '#d95926', '#199e70', '#c98500', '#d55181', '#008300'];
const MAX_PORCIONES = 6;

/** Gráfico de un reporte del CU14: barras horizontales, líneas o torta. */
@Component({
  selector: 'app-grafico-reporte',
  standalone: true,
  imports: [DecimalPipe],
  templateUrl: './grafico-reporte.html',
  styleUrl: './grafico-reporte.scss',
})
export class GraficoReporte {
  @Input({ required: true }) set datos(v: Punto[]) {
    this.puntos.set(v ?? []);
  }
  @Input({ required: true }) set tipo(v: Grafico) {
    this.forma.set(v);
  }
  /** moneda → "Bs 1.234"; numero → "1.234" */
  @Input() formato: 'moneda' | 'numero' = 'numero';
  @Input() etiquetaMedida = '';
  /** Escala compartida: con varios gráficos (uno por sucursal) todos usan el mismo máximo y se comparan a ojo. */
  @Input() set maximo(v: number | null | undefined) {
    this.maxFijo.set(v ?? null);
  }

  puntos = signal<Punto[]>([]);
  forma = signal<Grafico>('barras');
  hover = signal<number | null>(null);
  private maxFijo = signal<number | null>(null);

  max = computed(() => Math.max(1, this.maxFijo() ?? 0, ...this.puntos().map((p) => p.valor)));
  total = computed(() => this.puntos().reduce((a, p) => a + p.valor, 0) || 1);

  // ---------- líneas ----------
  readonly ancho = 640;
  readonly alto = 220;
  readonly margen = { izq: 56, der: 12, arr: 14, aba: 28 };
  techo = computed(() => this.escalaRedonda(this.max()));
  coords = computed(() => {
    const pts = this.puntos();
    const w = this.ancho - this.margen.izq - this.margen.der;
    const h = this.alto - this.margen.arr - this.margen.aba;
    const paso = pts.length > 1 ? w / (pts.length - 1) : 0;
    return pts.map((p, i) => ({
      x: this.margen.izq + (pts.length > 1 ? i * paso : w / 2),
      y: this.margen.arr + h - (p.valor / this.techo()) * h,
      ...p,
    }));
  });
  linea = computed(() => this.coords().map((c, i) => `${i ? 'L' : 'M'}${c.x.toFixed(1)},${c.y.toFixed(1)}`).join(' '));
  area = computed(() => {
    const c = this.coords();
    if (!c.length) return '';
    const base = this.alto - this.margen.aba;
    return `${this.linea()} L${c[c.length - 1].x.toFixed(1)},${base} L${c[0].x.toFixed(1)},${base} Z`;
  });
  guias = computed(() =>
    [0, 0.5, 1].map((f) => ({
      y: this.margen.arr + (this.alto - this.margen.arr - this.margen.aba) * (1 - f),
      valor: this.techo() * f,
    }))
  );
  pasoEtiquetas = computed(() => Math.max(1, Math.ceil(this.puntos().length / 7)));

  // ---------- torta ----------
  porciones = computed(() => {
    let pts = this.puntos().filter((p) => p.valor > 0);
    if (pts.length > MAX_PORCIONES) {
      const resto = pts.slice(MAX_PORCIONES - 1).reduce((a, p) => a + p.valor, 0);
      pts = [...pts.slice(0, MAX_PORCIONES - 1), { etiqueta: 'Otros', valor: resto }];
    }
    const total = pts.reduce((a, p) => a + p.valor, 0) || 1;
    let angulo = -Math.PI / 2;
    return pts.map((p, i) => {
      const fraccion = p.valor / total;
      const inicio = angulo;
      angulo += fraccion * 2 * Math.PI;
      return { ...p, pct: fraccion * 100, indice: i, camino: this.arco(inicio, angulo, fraccion) };
    });
  });

  colorClaro(i: number) {
    return PALETA_CLARO[i % PALETA_CLARO.length];
  }

  colorOscuro(i: number) {
    return PALETA_OSCURO[i % PALETA_OSCURO.length];
  }

  fmt(valor: number): string {
    const n = valor.toLocaleString('es-BO', { maximumFractionDigits: this.formato === 'moneda' ? 0 : 1 });
    return this.formato === 'moneda' ? `Bs ${n}` : n;
  }

  fmtCorto(valor: number): string {
    if (valor >= 1000) {
      const n = (valor / 1000).toLocaleString('es-BO', { maximumFractionDigits: 1 }) + ' mil';
      return this.formato === 'moneda' ? `Bs ${n}` : n;
    }
    return this.fmt(valor);
  }

  fechaCorta(etiqueta: string): string {
    return /^\d{4}-\d{2}-\d{2}$/.test(etiqueta)
      ? new Date(etiqueta + 'T00:00:00').toLocaleDateString('es-BO', { day: '2-digit', month: 'short' })
      : etiqueta;
  }

  private arco(inicio: number, fin: number, fraccion: number): string {
    const r = 90;
    const cx = 100;
    const cy = 100;
    if (fraccion >= 0.9999) return `M${cx},${cy - r} A${r},${r} 0 1 1 ${cx - 0.01},${cy - r} Z`;
    const x1 = cx + r * Math.cos(inicio);
    const y1 = cy + r * Math.sin(inicio);
    const x2 = cx + r * Math.cos(fin);
    const y2 = cy + r * Math.sin(fin);
    return `M${cx},${cy} L${x1.toFixed(2)},${y1.toFixed(2)} A${r},${r} 0 ${fraccion > 0.5 ? 1 : 0} 1 ${x2.toFixed(2)},${y2.toFixed(2)} Z`;
  }

  private escalaRedonda(max: number): number {
    const magnitud = Math.pow(10, Math.floor(Math.log10(max)));
    const paso = [1, 2, 2.5, 5, 10].find((p) => p * magnitud >= max) ?? 10;
    return paso * magnitud;
  }
}
