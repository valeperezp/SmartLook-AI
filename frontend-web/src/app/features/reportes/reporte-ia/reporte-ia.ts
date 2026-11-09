import { ChangeDetectorRef, Component, DestroyRef, OnDestroy, OnInit, computed, inject, signal } from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { IconComponent } from '../../../core/components/icon/icon';
import { AuthService } from '../../../core/services/auth.service';
import { CatalogoService } from '../../../core/services/catalogo.service';
import { ReportesService } from '../../../core/services/reportes.service';
import { SpeechService } from '../../../core/services/speech.service';
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

/** Un mensaje de la conversación: lo que pidió la persona o lo que respondió el sistema. */
interface Turno {
  rol: 'usuario' | 'asistente';
  texto: string;
}

/** CU14 — Solicitar reporte generativo: frase (escrita o dictada) → IA → reporte del catálogo permitido.
 *  Es una conversación: cada frase nueva se interpreta sobre el reporte que está en pantalla. */
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

  /** Conversación en curso y la intención del último reporte generado (el "contexto" de la charla). */
  conversacion = signal<Turno[]>([]);
  private contexto = signal<IntencionReporte | null>(null);
  enConversacion = computed(() => this.contexto() !== null);
  /** La última respuesta ya se ve en la tarjeta del reporte: en el hilo se muestran las anteriores. */
  turnosVisibles = computed(() => {
    const turnos = this.conversacion();
    const ultimo = turnos[turnos.length - 1];
    const enTarjeta = !this.cargando() && this.resultado()?.estado === 'ok' && ultimo?.rol === 'asistente';
    return enTarjeta ? turnos.slice(0, -1) : turnos;
  });

  // Dictado por voz (3a): Web Speech API del navegador, a través de SpeechService.
  private voz = inject(SpeechService);
  private destroyRef = inject(DestroyRef);
  private cdr = inject(ChangeDetectorRef);
  escuchando = this.voz.escuchando;
  errorVoz = this.voz.error;
  vozDisponible = this.voz.soportado;

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
  formatoMedida = computed<'moneda' | 'numero'>(() => (this.columnaMedida()?.tipo === 'moneda' ? 'moneda' : 'numero'));
  /** Máximo común a todos los gráficos por sucursal: misma escala, se comparan de un vistazo. */
  maxGrupos = computed(() =>
    Math.max(1, ...(this.resultado()?.grupos ?? []).flatMap((g) => g.puntos.map((p) => p.valor)))
  );

  ngOnInit() {
    // El texto dictado se coloca en el input mientras la persona habla; ella lo revisa y da "Generar" (3a).
    this.voz.transcripcion$.pipe(takeUntilDestroyed(this.destroyRef)).subscribe((t) => {
      this.solicitud = t.texto;
      this.cdr.markForCheck(); // `solicitud` no es una señal: se avisa para que el input se repinte
    });
    this.reportesService.catalogo().subscribe((c) => {
      this.catalogo.set(c);
      if (!c.plan_incluye_ia) this.mostrarConvencional.set(true);
    });
    this.sucursalesService.listar().subscribe((s) => this.sucursales.set(s.filter((x) => x.activa)));
    this.catalogoService.listarCategorias().subscribe((c: any[]) => this.categorias.set(c.filter((x) => x.activo !== false)));
    this.cargarHistorial();
  }

  ngOnDestroy() {
    this.voz.detenerEscucha();
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

  // ---------- flujo con IA (conversación) ----------
  /** Envía la frase. Si hay un reporte en pantalla, va como contexto: la frase puede ser un ajuste
   *  ("ahora solo Centro", "mostralo en torta") y la IA la interpreta sobre ese reporte. */
  generar(texto?: string, turnoVisible?: string) {
    const solicitud = (texto ?? this.solicitud).trim();
    if (solicitud.length < 3 || this.cargando()) return;
    this.cargando.set(true);
    this.error.set(null);
    this.agregarTurno('usuario', turnoVisible ?? solicitud);
    this.solicitud = '';
    this.reportesService.solicitar(solicitud, this.contexto()).subscribe({
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
    this.generar(`${this.ultimaSolicitud() ?? ''}, ${respuesta}`, respuesta);
  }

  /** Un ejemplo empieza una conversación nueva; una sugerencia la continúa. */
  usarEjemplo(ejemplo: string) {
    this.nuevaConsulta();
    this.generar(ejemplo);
  }

  seguir(sugerencia: string) {
    this.generar(sugerencia);
  }

  nuevaConsulta() {
    this.conversacion.set([]);
    this.contexto.set(null);
    this.resultado.set(null);
    this.ultimaSolicitud.set(null);
    this.error.set(null);
  }

  private agregarTurno(rol: Turno['rol'], texto: string) {
    this.conversacion.update((c) => [...c, { rol, texto }].slice(-12));
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
    this.nuevaConsulta();
    if (h.solicitud) this.agregarTurno('usuario', h.solicitud);
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
    if (r.estado === 'ok' || r.estado === 'sin_datos') {
      this.cargarHistorial();
      if (r.intencion) {
        const intencion: IntencionReporte & { descartados?: string[] } = { ...r.intencion };
        delete intencion.descartados;
        this.contexto.set(intencion); // el próximo pedido continúa sobre este reporte
      }
    }
    // La respuesta del sistema también queda en la conversación, en lenguaje natural.
    const respuesta =
      r.estado === 'ok' ? r.resumen || r.titulo : r.estado === 'aclaracion' ? r.pregunta : r.mensaje;
    if (respuesta) this.agregarTurno('asistente', respuesta);
  }

  // ---------- voz ----------
  dictar() {
    if (!this.vozDisponible) return;
    if (this.escuchando()) this.voz.detenerEscucha();
    else this.voz.iniciarEscucha();
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
    if (valor === null || valor === undefined || valor === '') return col.tipo === 'porcentaje' ? '—' : '';
    if (col.tipo === 'porcentaje') return `${Number(valor) > 0 ? '+' : ''}${Math.round(Number(valor))}%`;
    if (col.tipo === 'moneda') return 'Bs ' + Number(valor).toLocaleString('es-BO', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
    if (col.tipo === 'numero') return Number(valor).toLocaleString('es-BO');
    if (col.tipo === 'fecha') return new Date(valor + 'T00:00:00').toLocaleDateString('es-BO', { weekday: 'short', day: '2-digit', month: 'short' });
    return String(valor);
  }
}
