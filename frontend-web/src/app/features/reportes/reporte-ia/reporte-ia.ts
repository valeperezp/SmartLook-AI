import { Component, OnDestroy, OnInit, computed, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { IconComponent } from '../../../core/components/icon/icon';
import { AuthService } from '../../../core/services/auth.service';
import { CatalogoService } from '../../../core/services/catalogo.service';
import { ReportesService } from '../../../core/services/reportes.service';
import { SucursalesService } from '../../../core/services/sucursales.service';
import { Sucursal } from '../../../core/models/sucursal.model';
import {
  CatalogoReportes,
  ColumnaReporte,
  Grafico,
  HistorialReporte,
  IntencionReporte,
  ResultadoReporte,
} from '../../../core/models/reporte.model';
import { GraficoReporte } from '../shared/grafico-reporte';

/** CU14 — Solicitar reporte generativo: frase (escrita o dictada) → IA → reporte del catálogo permitido. */
@Component({
  selector: 'app-reporte-ia',
  standalone: true,
  imports: [CommonModule, FormsModule, RouterLink, IconComponent, GraficoReporte],
  templateUrl: './reporte-ia.html',
  styleUrl: './reporte-ia.scss',
})
export class ReporteIa implements OnInit, OnDestroy {
  private auth = inject(AuthService);
  private reportesService = inject(ReportesService);
  private sucursalesService = inject(SucursalesService);
  private catalogoService = inject(CatalogoService);

  readonly graficos: { id: Grafico; texto: string }[] = [
    { id: 'barras', texto: 'Barras' },
    { id: 'lineas', texto: 'Líneas' },
    { id: 'torta', texto: 'Torta' },
  ];

  isAdmin = this.auth.isAdmin;
  catalogo = signal<CatalogoReportes | null>(null);
  sucursales = signal<Sucursal[]>([]);
  categorias = signal<{ id: number; nombre: string }[]>([]);
  historial = signal<HistorialReporte[]>([]);

  solicitud = '';
  respuestaAclaracion = '';
  cargando = signal(false);
  exportando = signal<'pdf' | 'excel' | null>(null);
  resultado = signal<ResultadoReporte | null>(null);
  /** Frase con la que se generó el resultado en pantalla (para el PDF y para aclaraciones). */
  ultimaSolicitud = signal<string | null>(null);
  grafico = signal<Grafico>('barras');
  mostrarConvencional = signal(false);
  error = signal<string | null>(null);

  // Dictado por voz (3a): Web Speech API del navegador.
  escuchando = signal(false);
  vozDisponible = typeof window !== 'undefined' && !!((window as any).SpeechRecognition || (window as any).webkitSpeechRecognition);
  private reconocimiento: any = null;

  // Formulario de reportes convencionales (2a, 4a).
  conv: IntencionReporte & { sucursal?: number | null; categoria?: number | null } = this.convVacio();

  tipoConv = computed(() => this.catalogo()?.tipos.find((t) => t.id === this.convTipo()) ?? null);
  private convTipo = signal('ventas_por_sucursal');

  /** Puntos que dibuja el gráfico: la etiqueta y la medida principal del reporte. */
  puntos = computed(() => {
    const r = this.resultado();
    if (!r?.filas || !r.medida) return [];
    return r.filas.map((f) => ({ etiqueta: String(f['etiqueta']), valor: Number(f[r.medida!]) || 0 }));
  });
  columnaMedida = computed<ColumnaReporte | undefined>(() =>
    this.resultado()?.columnas?.find((c) => c.clave === this.resultado()?.medida)
  );

  ngOnInit() {
    this.reportesService.catalogo().subscribe((c) => {
      this.catalogo.set(c);
      if (!c.plan_incluye_ia) this.mostrarConvencional.set(true);
    });
    this.sucursalesService.listar().subscribe((s) => this.sucursales.set(s.filter((x) => x.activa)));
    this.catalogoService.listarCategorias().subscribe((c: any[]) => this.categorias.set(c.filter((x) => x.activo !== false)));
    this.cargarHistorial();
  }

  ngOnDestroy() {
    this.reconocimiento?.abort?.();
  }

  private convVacio() {
    const hoy = new Date();
    const inicio = new Date(hoy.getFullYear(), hoy.getMonth(), 1);
    return {
      tipo: 'ventas_por_sucursal',
      fecha_inicio: this.iso(inicio),
      fecha_fin: this.iso(hoy),
      sucursal: null,
      categoria: null,
      limite: 10,
    };
  }

  private iso(d: Date): string {
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
  }

  cargarHistorial() {
    this.reportesService.historial().subscribe((h) => this.historial.set(h));
  }

  // ---------- flujo con IA ----------
  generar(texto?: string) {
    const solicitud = (texto ?? this.solicitud).trim();
    if (solicitud.length < 3 || this.cargando()) return;
    this.solicitud = solicitud;
    this.cargando.set(true);
    this.error.set(null);
    this.reportesService.solicitar(solicitud).subscribe({
      next: (r) => this.mostrar(r, solicitud),
      error: (err) => {
        this.cargando.set(false);
        this.error.set(err.error?.detail || 'No se pudo generar el reporte');
      },
    });
  }

  /** 5a: el usuario responde la pregunta de aclaración y se vuelve a interpretar todo junto. */
  responderAclaracion() {
    const respuesta = this.respuestaAclaracion.trim();
    if (!respuesta) return;
    this.respuestaAclaracion = '';
    this.generar(`${this.ultimaSolicitud() ?? this.solicitud}, ${respuesta}`);
  }

  usarEjemplo(ejemplo: string) {
    this.solicitud = ejemplo;
    this.generar();
  }

  // ---------- reportes convencionales ----------
  cambiarTipoConv(id: string) {
    this.conv.tipo = id;
    this.convTipo.set(id);
  }

  ejecutarConvencional() {
    const tipo = this.tipoConv();
    if (!tipo) return;
    const intencion: IntencionReporte = {
      tipo: tipo.id,
      fecha_inicio: tipo.usa_fechas ? this.conv.fecha_inicio : null,
      fecha_fin: tipo.usa_fechas ? this.conv.fecha_fin : null,
      sucursal_ids: this.conv.sucursal ? [this.conv.sucursal] : [],
      categoria_ids: tipo.usa_categorias && this.conv.categoria ? [this.conv.categoria] : [],
      limite: tipo.usa_limite ? this.conv.limite : null,
    };
    this.ejecutarIntencion(intencion, null);
  }

  repetir(h: HistorialReporte) {
    this.solicitud = h.solicitud ?? '';
    this.ejecutarIntencion(h.intencion, h.solicitud);
  }

  private ejecutarIntencion(intencion: IntencionReporte, solicitud: string | null) {
    this.cargando.set(true);
    this.error.set(null);
    this.reportesService.ejecutar(intencion).subscribe({
      next: (r) => this.mostrar(r, solicitud),
      error: (err) => {
        this.cargando.set(false);
        this.error.set(err.error?.detail || 'No se pudo generar el reporte');
      },
    });
  }

  private mostrar(r: ResultadoReporte, solicitud: string | null) {
    this.cargando.set(false);
    this.resultado.set(r);
    this.ultimaSolicitud.set(solicitud);
    if (r.grafico) this.grafico.set(r.grafico);
    if (r.estado === 'ia_no_disponible' || r.estado === 'plan_sin_ia') this.mostrarConvencional.set(true);
    if (r.estado === 'ok' || r.estado === 'sin_datos') this.cargarHistorial();
  }

  // ---------- voz ----------
  dictar() {
    if (!this.vozDisponible) return;
    if (this.escuchando()) {
      this.reconocimiento?.stop();
      return;
    }
    const Ctor = (window as any).SpeechRecognition || (window as any).webkitSpeechRecognition;
    this.reconocimiento = new Ctor();
    this.reconocimiento.lang = 'es-BO';
    this.reconocimiento.interimResults = false;
    this.reconocimiento.onresult = (e: any) => {
      // Se muestra el texto para que el usuario lo revise antes de generar (3a).
      this.solicitud = Array.from(e.results).map((res: any) => res[0].transcript).join(' ');
    };
    this.reconocimiento.onend = () => this.escuchando.set(false);
    this.reconocimiento.onerror = () => this.escuchando.set(false);
    this.escuchando.set(true);
    this.reconocimiento.start();
  }

  // ---------- exportar ----------
  exportar(formato: 'pdf' | 'excel') {
    const r = this.resultado();
    if (!r?.intencion || this.exportando()) return;
    this.exportando.set(formato);
    const intencion = { ...r.intencion, grafico: this.grafico() };
    delete (intencion as any).descartados;
    this.reportesService.exportarReporte(formato, intencion, this.ultimaSolicitud()).subscribe({
      next: (blob) => {
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = `${(r.titulo || 'reporte').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/[^a-z0-9]+/g, '-')}.${formato === 'pdf' ? 'pdf' : 'xlsx'}`;
        document.body.appendChild(a);
        a.click();
        a.remove();
        URL.revokeObjectURL(url);
        this.exportando.set(null);
      },
      error: () => {
        this.exportando.set(null);
        this.error.set('No se pudo exportar el reporte');
      },
    });
  }

  celda(col: ColumnaReporte, valor: any): string {
    if (valor === null || valor === undefined || valor === '') return '';
    if (col.tipo === 'moneda') return 'Bs ' + Number(valor).toLocaleString('es-BO', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
    if (col.tipo === 'numero') return Number(valor).toLocaleString('es-BO');
    if (col.tipo === 'fecha') return new Date(valor + 'T00:00:00').toLocaleDateString('es-BO', { weekday: 'short', day: '2-digit', month: 'short' });
    return String(valor);
  }
}
