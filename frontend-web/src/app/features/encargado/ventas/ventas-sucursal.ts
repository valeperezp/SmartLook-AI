import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { CommonModule, CurrencyPipe, DatePipe } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { IconComponent } from '../../../core/components/icon/icon';
import { VentasService } from '../../../core/services/ventas.service';
import { PagosService } from '../../../core/services/pagos.service';
import { AuthService } from '../../../core/services/auth.service';
import { Venta } from '../../../core/models/venta.model';
import { Pago } from '../../../core/models/pago.model';

@Component({
  selector: 'app-ventas-sucursal',
  standalone: true,
  imports: [CommonModule, FormsModule, IconComponent, CurrencyPipe, DatePipe],
  templateUrl: './ventas-sucursal.html',
  styleUrl: './ventas-sucursal.scss',
})
export class VentasSucursal implements OnInit {
  private ventasService = inject(VentasService);
  private pagosService = inject(PagosService);
  private auth = inject(AuthService);

  user = this.auth.currentUser;

  ventas = signal<Venta[]>([]);
  cargando = signal<boolean>(true);
  error = signal<string | null>(null);

  filtroFecha = signal<'hoy' | 'semana' | 'mes' | 'todas'>('hoy');
  filtroCanal = signal<'todos' | 'presencial' | 'online'>('todos');
  filtroEstado = signal<'todos' | 'completada' | 'pendiente' | 'cancelada'>('todos');
  busqueda = signal<string>('');

  ventaSeleccionada = signal<Venta | null>(null);
  modalDetalleAbierto = signal<boolean>(false);
  pagosVenta = signal<Pago[]>([]);
  cargandoPagos = signal<boolean>(false);

  toast = signal<string | null>(null);

  ventasFiltradas = computed(() => {
    const ahora = new Date();
    const hoyInicio = new Date(ahora.getFullYear(), ahora.getMonth(), ahora.getDate(), 0, 0, 0).getTime();
    const semanaInicio = ahora.getTime() - 7 * 24 * 60 * 60 * 1000;
    const mesInicio = new Date(ahora.getFullYear(), ahora.getMonth(), 1, 0, 0, 0).getTime();

    const fFecha = this.filtroFecha();
    const fCanal = this.filtroCanal();
    const fEstado = this.filtroEstado();
    const q = this.busqueda().toLowerCase().trim();

    return this.ventas()
      .filter((v) => {
        const time = new Date(v.creada_en).getTime();

        // Filtro por fecha
        if (fFecha === 'hoy' && time < hoyInicio) return false;
        if (fFecha === 'semana' && time < semanaInicio) return false;
        if (fFecha === 'mes' && time < mesInicio) return false;

        // Filtro por canal
        if (fCanal !== 'todos' && v.canal !== fCanal) return false;

        // Filtro por estado
        if (fEstado !== 'todos' && v.estado !== fEstado) return false;

        // Búsqueda
        if (q) {
          const matchId = String(v.id).includes(q);
          const matchCliente = v.nombre_cliente?.toLowerCase().includes(q) ?? false;
          const matchCajero = v.nombre_cajero?.toLowerCase().includes(q) ?? false;
          if (!matchId && !matchCliente && !matchCajero) return false;
        }

        return true;
      })
      .sort((a, b) => new Date(b.creada_en).getTime() - new Date(a.creada_en).getTime());
  });

  totalVentas = computed(() => this.ventasFiltradas().length);

  montoTotal = computed(() => {
    return this.ventasFiltradas().reduce((sum, v) => sum + Number(v.total), 0);
  });

  ticketPromedio = computed(() => {
    const count = this.totalVentas();
    return count > 0 ? this.montoTotal() / count : 0;
  });

  unidadesVendidas = computed(() => {
    return this.ventasFiltradas().reduce((sum, v) => sum + (Number(v.total_unidades) || 0), 0);
  });

  ngOnInit() {
    this.cargar();
  }

  cargar() {
    const sucursalId = this.user()?.sucursal_id || 1;
    this.cargando.set(true);
    this.error.set(null);

    this.ventasService.listarPorSucursal(sucursalId).subscribe({
      next: (data) => {
        this.ventas.set(data || []);
        this.cargando.set(false);
      },
      error: (err) => {
        console.error('Error al cargar ventas de sucursal', err);
        this.error.set(err.error?.detail || 'No se pudieron cargar las ventas de la sucursal');
        this.cargando.set(false);
      },
    });
  }

  setFecha(filtro: 'hoy' | 'semana' | 'mes' | 'todas') {
    this.filtroFecha.set(filtro);
  }

  setCanal(filtro: 'todos' | 'presencial' | 'online') {
    this.filtroCanal.set(filtro);
  }

  setEstado(filtro: 'todos' | 'completada' | 'pendiente' | 'cancelada') {
    this.filtroEstado.set(filtro);
  }

  abrirDetalle(venta: Venta) {
    this.ventaSeleccionada.set(venta);
    this.modalDetalleAbierto.set(true);
    this.pagosVenta.set([]);
    this.cargandoPagos.set(true);

    this.pagosService.listarPorVenta(venta.id).subscribe({
      next: (pagos) => {
        this.pagosVenta.set(pagos || []);
        this.cargandoPagos.set(false);
      },
      error: () => {
        this.cargandoPagos.set(false);
      },
    });
  }

  cerrarDetalle() {
    this.modalDetalleAbierto.set(false);
    this.ventaSeleccionada.set(null);
    this.pagosVenta.set([]);
  }

  exportarCSV() {
    const lista = this.ventasFiltradas();
    if (lista.length === 0) {
      this.mostrarToast('No hay datos para exportar con los filtros actuales');
      return;
    }

    const headers = ['Ticket #', 'Fecha', 'Cliente', 'Cajero', 'Canal', 'Items', 'Unidades', 'Total', 'Estado'];
    const rows = lista.map((v) => [
      `#${v.id}`,
      `"${new Date(v.creada_en).toLocaleString()}"`,
      `"${v.nombre_cliente || 'Cliente Presencial'}"`,
      `"${v.nombre_cajero || '-'}"`,
      `"${v.canal}"`,
      v.total_items || 0,
      v.total_unidades || 0,
      Number(v.total).toFixed(2),
      `"${v.estado}"`,
    ]);

    const csvContent = [headers.join(','), ...rows.map((r) => r.join(','))].join('\n');
    const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.setAttribute('href', url);
    link.setAttribute('download', `ventas_sucursal_${this.user()?.sucursal_id || 1}_${Date.now()}.csv`);
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    URL.revokeObjectURL(url);

    this.mostrarToast('Archivo CSV exportado exitosamente');
  }

  mostrarToast(msg: string) {
    this.toast.set(msg);
    setTimeout(() => {
      if (this.toast() === msg) {
        this.toast.set(null);
      }
    }, 3500);
  }
}
