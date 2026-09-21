import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { IconComponent } from '../../../core/components/icon/icon';
import { AuthService } from '../../../core/services/auth.service';
import { ReportesService } from '../../../core/services/reportes.service';
import { ReportesChatService } from '../../../core/services/reportes-chat.service';
import { SucursalesService } from '../../../core/services/sucursales.service';
import { Sucursal } from '../../../core/models/sucursal.model';
import {
  ProductoMasReservado,
  ReservasPorDia,
  ReservasPorEstado,
  ReservasPorSucursal,
  ResumenReportes,
} from '../../../core/models/reporte.model';

@Component({
  selector: 'app-reportes-page',
  standalone: true,
  imports: [CommonModule, FormsModule, IconComponent],
  templateUrl: './reportes-page.html',
  styleUrl: './reportes-page.scss',
})
export class ReportesPage implements OnInit {
  private auth = inject(AuthService);
  private reportesService = inject(ReportesService);
  private sucursalesService = inject(SucursalesService);
  private reportesChatService = inject(ReportesChatService);

  isAdmin = this.auth.isAdmin;

  sucursales = signal<Sucursal[]>([]);
  sucursalId = signal<number | undefined>(undefined);

  cargando = signal<boolean>(true);
  exportando = signal<'pdf' | 'excel' | null>(null);
  resumen = signal<ResumenReportes | null>(null);
  porEstado = signal<ReservasPorEstado[]>([]);
  porSucursal = signal<ReservasPorSucursal[]>([]);
  topProductos = signal<ProductoMasReservado[]>([]);
  porDia = signal<ReservasPorDia[]>([]);

  maxPorDia = computed(() => Math.max(1, ...this.porDia().map((d) => d.cantidad)));
  maxUnidadesTop = computed(() => Math.max(1, ...this.topProductos().map((p) => p.total_unidades)));
  totalPorEstado = computed(() => this.porEstado().reduce((acc, e) => acc + e.cantidad, 0) || 1);

  ngOnInit() {
    if (this.isAdmin()) {
      this.sucursalesService.listar().subscribe({
        next: (data) => this.sucursales.set(data),
      });
      this.reportesService.reservasPorSucursal().subscribe({
        next: (data) => this.porSucursal.set(data),
      });
    }
    this.cargarDatos();
  }

  onSucursalChange(value: string) {
    this.sucursalId.set(value ? Number(value) : undefined);
    this.cargarDatos();
  }

  cargarDatos() {
    this.cargando.set(true);
    const sucursalId = this.sucursalId();

    this.reportesService.resumen(sucursalId).subscribe({
      next: (data) => {
        this.resumen.set(data);
        this.cargando.set(false);
      },
      error: () => this.cargando.set(false),
    });

    this.reportesService.reservasPorEstado(sucursalId).subscribe({
      next: (data) => this.porEstado.set(data),
    });

    this.reportesService.productosMasReservados(sucursalId, 8).subscribe({
      next: (data) => this.topProductos.set(data),
    });

    this.reportesService.reservasPorDia(sucursalId, 14).subscribe({
      next: (data) => this.porDia.set(data),
    });
  }

  exportarPDF() {
    if (this.exportando()) return;
    this.exportando.set('pdf');
    this.reportesService.exportarPdf(this.sucursalId()).subscribe({
      next: (blob) => this.descargarArchivo(blob, 'pdf'),
      error: () => this.exportando.set(null),
    });
  }

  exportarExcel() {
    if (this.exportando()) return;
    this.exportando.set('excel');
    this.reportesService.exportarExcel(this.sucursalId()).subscribe({
      next: (blob) => this.descargarArchivo(blob, 'xlsx'),
      error: () => this.exportando.set(null),
    });
  }

  abrirReporteDinamico() {
    this.reportesChatService.abrir(this.sucursalId());
  }

  private descargarArchivo(blob: Blob, extension: string) {
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

  estadoClass(estado: string): string {
    switch (estado) {
      case 'atendida':
        return 'badge-success';
      case 'confirmada':
        return 'badge-info';
      case 'cancelada':
        return 'badge-danger';
      default:
        return 'badge-warning';
    }
  }

  estadoPct(cantidad: number): number {
    return Math.round((cantidad / this.totalPorEstado()) * 100);
  }

  formatFecha(fecha: string): string {
    const d = new Date(fecha + 'T00:00:00');
    return d.toLocaleDateString('es-BO', { day: '2-digit', month: 'short' });
  }
}
