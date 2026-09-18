import { Component, OnInit, OnDestroy, inject, signal, computed } from '@angular/core';
import { CommonModule, CurrencyPipe, DatePipe } from '@angular/common';
import { IconComponent } from '../../../core/components/icon/icon';
import { PagosService } from '../../../core/services/pagos.service';
import { Pago } from '../../../core/models/pago.model';

@Component({
  selector: 'app-pagos-pendientes',
  standalone: true,
  imports: [CommonModule, IconComponent, CurrencyPipe, DatePipe],
  templateUrl: './pagos-pendientes.html',
  styleUrl: './pagos-pendientes.scss',
})
export class PagosPendientes implements OnInit, OnDestroy {
  private pagosService = inject(PagosService);

  pagos = signal<Pago[]>([]);
  cargando = signal<boolean>(true);
  errorCarga = signal<boolean>(false);
  toast = signal<string | null>(null);
  toastIsError = signal<boolean>(false);
  pagoSeleccionado = signal<Pago | null>(null);
  modalDetalleAbierto = signal<boolean>(false);
  procesando = signal<boolean>(false);

  totalPendientes = computed(() => this.pagos().length);
  montoTotalPendiente = computed(() => this.pagos().reduce((sum, p) => sum + p.monto, 0));

  private pollInterval: any = null;

  ngOnInit() {
    this.cargar();
    this.pollInterval = setInterval(() => {
      this.cargar(true);
    }, 10000);
  }

  ngOnDestroy() {
    if (this.pollInterval) {
      clearInterval(this.pollInterval);
      this.pollInterval = null;
    }
  }

  cargar(silencioso = false) {
    if (!silencioso) {
      this.cargando.set(true);
    }
    this.errorCarga.set(false);

    this.pagosService.listarPendientesVerificacion().subscribe({
      next: (data) => {
        this.pagos.set(data || []);
        this.cargando.set(false);

        // Si el pago seleccionado en modal ya no está pendiente, actualizar o cerrar
        const actual = this.pagoSeleccionado();
        if (actual) {
          const encontrado = (data || []).find((p) => p.id === actual.id);
          if (encontrado) {
            this.pagoSeleccionado.set(encontrado);
          } else {
            this.cerrarDetalle();
          }
        }
      },
      error: (err) => {
        console.error('Error al cargar pagos pendientes', err);
        if (!silencioso) {
          this.errorCarga.set(true);
        }
        this.cargando.set(false);
      },
    });
  }

  abrirDetalle(pago: Pago) {
    this.pagoSeleccionado.set(pago);
    this.modalDetalleAbierto.set(true);
  }

  cerrarDetalle() {
    this.modalDetalleAbierto.set(false);
    this.pagoSeleccionado.set(null);
  }

  verComprobante(pago: Pago, event?: Event) {
    if (event) {
      event.stopPropagation();
    }
    if (pago.comprobante_url) {
      window.open(pago.comprobante_url, '_blank');
    }
  }

  confirmarPago(pago: Pago, event?: Event) {
    if (event) {
      event.stopPropagation();
    }

    const montoTxt = pago.monto_formateado || `$${pago.monto.toFixed(2)}`;
    const seguro = window.confirm(`¿Confirmar el pago #${pago.id} de ${montoTxt} para la Venta #${pago.venta_id}?`);
    if (!seguro) return;

    this.procesando.set(true);
    this.pagosService.confirmarPagoQR(pago.id, true).subscribe({
      next: () => {
        this.procesando.set(false);
        this.cerrarDetalle();
        this.mostrarToast(`Pago #${pago.id} confirmado exitosamente`, false);
        this.cargar(true);
      },
      error: (err) => {
        this.procesando.set(false);
        const msg = err.error?.detail || 'Error al confirmar el pago';
        this.mostrarToast(msg, true);
      },
    });
  }

  rechazarPago(pago: Pago, event?: Event) {
    if (event) {
      event.stopPropagation();
    }

    const motivo = window.prompt(`Ingresá el motivo del rechazo del comprobante (Pago #${pago.id}):`);
    if (motivo === null) return;

    this.procesando.set(true);
    this.pagosService.confirmarPagoQR(pago.id, false, motivo.trim() || undefined).subscribe({
      next: () => {
        this.procesando.set(false);
        this.cerrarDetalle();
        this.mostrarToast(`Pago #${pago.id} rechazado`, false);
        this.cargar(true);
      },
      error: (err) => {
        this.procesando.set(false);
        const msg = err.error?.detail || 'Error al rechazar el pago';
        this.mostrarToast(msg, true);
      },
    });
  }

  mostrarToast(msg: string, isError = false) {
    this.toast.set(msg);
    this.toastIsError.set(isError);
    setTimeout(() => {
      if (this.toast() === msg) {
        this.toast.set(null);
      }
    }, 4000);
  }
}
