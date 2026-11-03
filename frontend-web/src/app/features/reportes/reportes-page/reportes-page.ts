import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { IconComponent } from '../../../core/components/icon/icon';
import { AuthService } from '../../../core/services/auth.service';
import { ReportesService } from '../../../core/services/reportes.service';
import { SucursalesService } from '../../../core/services/sucursales.service';
import { Sucursal } from '../../../core/models/sucursal.model';
import { Dashboard, VentasPorDia } from '../../../core/models/reporte.model';
import { Analitica } from '../../../core/models/analitica.model';
import { AnaliticaService } from '../../../core/services/analitica.service';

/** Fila de un ranking de barras horizontales (un solo tono: es una sola medida). */
interface FilaRanking {
  etiqueta: string;
  detalle?: string;
  valor: number;
  texto: string;
}

/** CU15 — Consultar dashboard analítico (admin: toda la empresa o una sucursal; encargado: su sucursal). */
@Component({
  selector: 'app-reportes-page',
  standalone: true,
  imports: [CommonModule, FormsModule, RouterLink, IconComponent],
  templateUrl: './reportes-page.html',
  styleUrl: './reportes-page.scss',
})
export class ReportesPage implements OnInit {
  private auth = inject(AuthService);
  private reportesService = inject(ReportesService);
  private sucursalesService = inject(SucursalesService);
  private analiticaService = inject(AnaliticaService);

  readonly periodos = [
    { dias: 7, texto: '7 días' },
    { dias: 30, texto: '30 días' },
    { dias: 90, texto: '90 días' },
  ];

  isAdmin = this.auth.isAdmin;
  sucursales = signal<Sucursal[]>([]);
  sucursalId = signal<number | undefined>(undefined);
  dias = signal(30);
  cargando = signal(true);
  error = signal<string | null>(null);
  exportando = signal<'pdf' | 'excel' | null>(null);
  datos = signal<Dashboard | null>(null);
  hover = signal<number | null>(null);
  verTabla = signal(false);

  // ---------- serie diaria ----------
  serie = computed<VentasPorDia[]>(() => this.datos()?.ventas_por_dia ?? []);
  maxIngresos = computed(() => this.escalaRedonda(Math.max(0, ...this.serie().map((d) => d.ingresos))));
  guias = computed(() => [1, 0.5].map((f) => ({ pct: f * 100, valor: this.maxIngresos() * f })));
  /** Con 90 barras no entran todas las fechas: se rotula cada tanto. */
  pasoEtiquetas = computed(() => Math.max(1, Math.ceil(this.serie().length / 8)));
  diaHover = computed(() => {
    const i = this.hover();
    return i === null ? null : this.serie()[i] ?? null;
  });

  // ---------- rankings ----------
  porSucursal = computed<FilaRanking[]>(() =>
    (this.datos()?.ventas_por_sucursal ?? []).map((s) => ({
      etiqueta: s.nombre_sucursal,
      detalle: `${s.cantidad_ventas} ventas`,
      valor: s.ingresos,
      texto: this.bs(s.ingresos),
    }))
  );
  porCategoria = computed<FilaRanking[]>(() =>
    (this.datos()?.ventas_por_categoria ?? []).map((c) => ({
      etiqueta: c.categoria,
      detalle: `${c.unidades} u.`,
      valor: c.ingresos,
      texto: this.bs(c.ingresos),
    }))
  );
  porCanal = computed<FilaRanking[]>(() =>
    (this.datos()?.ventas_por_canal ?? [])
      .slice()
      .sort((a, b) => b.ingresos - a.ingresos)
      .map((c) => ({
        etiqueta: c.canal === 'online' ? 'Online' : 'Presencial',
        detalle: `${c.cantidad} ventas`,
        valor: c.ingresos,
        texto: this.bs(c.ingresos),
      }))
  );
  topVendidos = computed<FilaRanking[]>(() =>
    (this.datos()?.top_vendidos ?? []).map((p) => ({
      etiqueta: p.nombre_producto,
      detalle: p.nombre_categoria ?? undefined,
      valor: p.unidades,
      texto: `${p.unidades} u.`,
    }))
  );

  // ---------- Machine Learning (CU15) ----------
  ml = signal<Analitica | null>(null);
  mlBloqueado = signal<string | null>(null); // RN-05: plan sin IA
  entrenando = signal(false);
  mlError = signal<string | null>(null);
  hoverDemanda = signal<number | null>(null);

  /** Últimos 30 días reales seguidos de los 30 predichos, en una sola serie temporal. */
  serieDemanda = computed(() => {
    const d = this.ml()?.demanda;
    if (!d) return [];
    return [
      ...d.historico.map((p) => ({ ...p, predicho: false })),
      ...d.prediccion.map((p) => ({ ...p, predicho: true })),
    ];
  });
  maxDemanda = computed(() => this.escalaRedonda(Math.max(0, ...this.serieDemanda().map((p) => p.unidades))));
  inicioPrediccion = computed(() => this.ml()?.demanda?.historico.length ?? 0);
  puntoDemanda = computed(() => {
    const i = this.hoverDemanda();
    return i === null ? null : this.serieDemanda()[i] ?? null;
  });
  segmentosFilas = computed<FilaRanking[]>(() =>
    (this.ml()?.segmentos?.segmentos ?? []).map((s) => ({
      etiqueta: s.segmento,
      detalle: `${s.pct_ingresos}% de los ingresos`,
      valor: s.clientes,
      texto: `${s.clientes} clientes`,
    }))
  );
  modeloDemanda = computed(() => this.ml()?.modelos.find((m) => m.tipo === 'demanda') ?? null);
  modeloSegmentos = computed(() => this.ml()?.modelos.find((m) => m.tipo === 'segmentacion') ?? null);

  ngOnInit() {
    if (this.isAdmin()) {
      this.sucursalesService.listar().subscribe((data) => this.sucursales.set(data));
    }
    this.cargar();
  }

  cargarML() {
    this.mlError.set(null);
    this.analiticaService.consultar(this.sucursalId()).subscribe({
      next: (data) => {
        this.ml.set(data);
        this.mlBloqueado.set(null);
      },
      error: (err) => {
        if (err.status === 403) this.mlBloqueado.set(err.error?.detail || 'Disponible en el plan Profesional');
        else this.mlError.set('No se pudieron cargar los resultados de los modelos');
      },
    });
  }

  entrenar() {
    if (this.entrenando()) return;
    this.entrenando.set(true);
    this.mlError.set(null);
    this.analiticaService.entrenar().subscribe({
      next: () => {
        this.entrenando.set(false);
        this.cargarML();
      },
      error: (err) => {
        this.entrenando.set(false);
        this.mlError.set(err.error?.detail || 'No se pudieron entrenar los modelos');
      },
    });
  }

  metrica(valor: number | null | undefined, decimales = 2): string {
    return valor === null || valor === undefined ? '—' : valor.toLocaleString('es-BO', { maximumFractionDigits: decimales });
  }

  cargar() {
    this.cargarML();
    this.cargando.set(true);
    this.error.set(null);
    this.reportesService.dashboard(this.sucursalId(), this.dias()).subscribe({
      next: (data) => {
        this.datos.set(data);
        this.cargando.set(false);
      },
      error: (err) => {
        this.cargando.set(false);
        this.error.set(err.error?.detail || 'No se pudo cargar el dashboard');
      },
    });
  }

  cambiarSucursal(value: string) {
    this.sucursalId.set(value ? Number(value) : undefined);
    this.cargar();
  }

  cambiarPeriodo(dias: number) {
    if (dias === this.dias()) return;
    this.dias.set(dias);
    this.cargar();
  }

  exportar(formato: 'pdf' | 'excel') {
    if (this.exportando()) return;
    this.exportando.set(formato);
    this.reportesService.exportar(formato, this.sucursalId(), this.dias()).subscribe({
      next: (blob) => this.descargar(blob, formato === 'pdf' ? 'pdf' : 'xlsx'),
      error: () => this.exportando.set(null),
    });
  }

  private descargar(blob: Blob, extension: string) {
    const fecha = new Date().toISOString().slice(0, 10);
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = `reporte-smartlook-${fecha}.${extension}`;
    document.body.appendChild(link);
    link.click();
    link.remove();
    URL.revokeObjectURL(url);
    this.exportando.set(null);
  }

  // ---------- helpers de formato ----------
  bs(valor: number): string {
    return 'Bs ' + valor.toLocaleString('es-BO', { minimumFractionDigits: 0, maximumFractionDigits: 0 });
  }

  /** Mismo separador de miles que los montos (es-BO), para que no se mezclen formatos. */
  num(valor: number): string {
    return valor.toLocaleString('es-BO');
  }

  bsCorto(valor: number): string {
    if (valor >= 1000) return 'Bs ' + (valor / 1000).toLocaleString('es-BO', { maximumFractionDigits: 1 }) + ' mil';
    return this.bs(valor);
  }

  fechaCorta(fecha: string): string {
    return new Date(fecha + 'T00:00:00').toLocaleDateString('es-BO', { day: '2-digit', month: 'short' });
  }

  fechaLarga(fecha: string): string {
    return new Date(fecha + 'T00:00:00').toLocaleDateString('es-BO', { weekday: 'long', day: 'numeric', month: 'long' });
  }

  pctBarra(valor: number, filas: FilaRanking[]): number {
    const max = Math.max(1, ...filas.map((f) => f.valor));
    return (valor / max) * 100;
  }

  estadoClass(estado: string): string {
    switch (estado) {
      case 'atendida':
        return 'badge-success';
      case 'cancelada':
        return 'badge-danger';
      case 'confirmada':
        return 'badge-muted';
      default:
        return 'badge-warning';
    }
  }

  /** Techo "redondo" para el eje (1, 2, 2.5 o 5 × 10^n), para que las guías tengan números legibles. */
  escalaRedonda(max: number): number {
    if (max <= 0) return 1;
    const magnitud = Math.pow(10, Math.floor(Math.log10(max)));
    const paso = [1, 2, 2.5, 5, 10].find((p) => p * magnitud >= max) ?? 10;
    return paso * magnitud;
  }
}
