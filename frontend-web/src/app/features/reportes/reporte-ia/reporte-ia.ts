import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { IconComponent } from '../../../core/components/icon/icon';
import { AuthService } from '../../../core/services/auth.service';
import { ReportesService } from '../../../core/services/reportes.service';
import { SucursalesService } from '../../../core/services/sucursales.service';
import { Sucursal } from '../../../core/models/sucursal.model';
import { ReporteGenerativo } from '../../../core/models/reporte.model';

interface Fragmento {
  texto: string;
  negrita: boolean;
}

interface Bloque {
  tipo: 'titulo' | 'subtitulo' | 'vineta' | 'parrafo';
  partes: Fragmento[];
}

const SUGERENCIAS = [
  'Resumen de ventas de la última semana',
  '¿Qué categorías venden más este mes y qué me recomendás reponer?',
  'Reporte de inventario con las prendas en riesgo de agotarse',
  'Compará el rendimiento de las sucursales en los últimos 30 días',
];

/** CU14 — Solicitar reporte generativo (IA) y exportarlo a PDF o Excel. */
@Component({
  selector: 'app-reporte-ia',
  standalone: true,
  imports: [CommonModule, FormsModule, RouterLink, IconComponent],
  templateUrl: './reporte-ia.html',
  styleUrl: './reporte-ia.scss',
})
export class ReporteIa implements OnInit {
  private auth = inject(AuthService);
  private reportesService = inject(ReportesService);
  private sucursalesService = inject(SucursalesService);

  readonly sugerencias = SUGERENCIAS;
  readonly periodos: { valor: number | null; texto: string }[] = [
    { valor: null, texto: 'Según lo que pida' },
    { valor: 7, texto: 'Últimos 7 días' },
    { valor: 30, texto: 'Últimos 30 días' },
    { valor: 90, texto: 'Últimos 90 días' },
  ];

  isAdmin = this.auth.isAdmin;
  sucursales = signal<Sucursal[]>([]);

  solicitud = '';
  sucursalId: number | null = null;
  dias: number | null = null;

  generando = signal(false);
  exportando = signal<'pdf' | 'excel' | null>(null);
  error = signal<string | null>(null);
  reporte = signal<ReporteGenerativo | null>(null);
  editando = signal(false);
  textoEditado = '';

  bloques = computed<Bloque[]>(() => this.aBloques(this.reporte()?.contenido ?? ''));

  ngOnInit() {
    if (this.isAdmin()) {
      this.sucursalesService.listar().subscribe((s) => this.sucursales.set(s.filter((x) => x.activa)));
    }
  }

  usarSugerencia(texto: string) {
    this.solicitud = texto;
    this.generar();
  }

  generar() {
    const solicitud = this.solicitud.trim();
    if (solicitud.length < 3 || this.generando()) return;
    this.generando.set(true);
    this.error.set(null);
    this.editando.set(false);
    this.reportesService.generarReporte(solicitud, this.sucursalId ?? undefined, this.dias).subscribe({
      next: (r) => {
        this.reporte.set(r);
        this.generando.set(false);
      },
      error: (err) => {
        this.generando.set(false);
        this.error.set(err.error?.detail || 'No se pudo generar el reporte. Probá de nuevo.');
      },
    });
  }

  editar() {
    this.textoEditado = this.reporte()?.contenido ?? '';
    this.editando.set(true);
  }

  guardarEdicion() {
    const r = this.reporte();
    if (!r) return;
    this.reporte.set({ ...r, contenido: this.textoEditado });
    this.editando.set(false);
  }

  exportar(formato: 'pdf' | 'excel') {
    const r = this.reporte();
    if (!r || this.exportando()) return;
    this.exportando.set(formato);
    this.reportesService.exportarReporteGenerativo(formato, r, this.sucursalId ?? undefined).subscribe({
      next: (blob) => {
        const url = URL.createObjectURL(blob);
        const link = document.createElement('a');
        link.href = url;
        link.download = `${this.slug(r.titulo)}.${formato === 'pdf' ? 'pdf' : 'xlsx'}`;
        document.body.appendChild(link);
        link.click();
        link.remove();
        URL.revokeObjectURL(url);
        this.exportando.set(null);
      },
      error: () => {
        this.exportando.set(null);
        this.error.set('No se pudo exportar el reporte');
      },
    });
  }

  private slug(texto: string): string {
    return (
      texto
        .toLowerCase()
        .normalize('NFD')
        .replace(/[̀-ͯ]/g, '')
        .replace(/[^a-z0-9]+/g, '-')
        .replace(/^-+|-+$/g, '')
        .slice(0, 50) || 'reporte'
    );
  }

  /** Markdown mínimo (#, ##, viñetas, **negrita**) a bloques. Sin innerHTML: el texto viene del modelo. */
  private aBloques(contenido: string): Bloque[] {
    const bloques: Bloque[] = [];
    for (const cruda of contenido.split('\n')) {
      const linea = cruda.trim();
      if (!linea) continue;
      let tipo: Bloque['tipo'] = 'parrafo';
      let texto = linea;
      if (/^#\s/.test(linea)) {
        tipo = 'titulo';
        texto = linea.replace(/^#+\s*/, '');
      } else if (/^#{2,}/.test(linea)) {
        tipo = 'subtitulo';
        texto = linea.replace(/^#+\s*/, '');
      } else if (/^([-*•]|\d+[.)])\s+/.test(linea)) {
        tipo = 'vineta';
        texto = linea.replace(/^([-*•]|\d+[.)])\s+/, '');
      }
      bloques.push({ tipo, partes: this.negritas(texto) });
    }
    return bloques;
  }

  private negritas(texto: string): Fragmento[] {
    return texto
      .split(/(\*\*[^*]+\*\*)/g)
      .filter(Boolean)
      .map((p) => (p.startsWith('**') && p.endsWith('**') ? { texto: p.slice(2, -2), negrita: true } : { texto: p, negrita: false }));
  }
}
