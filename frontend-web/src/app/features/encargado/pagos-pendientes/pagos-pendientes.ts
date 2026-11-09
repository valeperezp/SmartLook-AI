import { Component, OnInit, OnDestroy, inject, signal, computed } from '@angular/core';
import { CommonModule, CurrencyPipe, DatePipe } from '@angular/common';
import { IconComponent } from '../../../core/components/icon/icon';
import { PagosService } from '../../../core/services/pagos.service';
import { DevolucionesService } from '../../../core/services/devoluciones.service';
import { Pago } from '../../../core/models/pago.model';
import { ReembolsoDetalle } from '../../../core/models/reserva.model';

@Component({
  selector: 'app-pagos-pendientes',
  standalone: true,
  imports: [CommonModule, IconComponent, CurrencyPipe, DatePipe],
  templateUrl: './pagos-pendientes.html',
  styleUrl: './pagos-pendientes.scss',
})
export class PagosPendientes implements OnInit, OnDestroy {
  private pagosService = inject(PagosService);
  private devolucionesService = inject(DevolucionesService);

  pagos = signal<Pago[]>([]);
  cargando = signal<boolean>(true);
  errorCarga = signal<boolean>(false);
  toast = signal<string | null>(null);
  toastIsError = signal<boolean>(false);
  pagoSeleccionado = signal<Pago | null>(null);
  modalDetalleAbierto = signal<boolean>(false);
  procesando = signal<boolean>(false);

  /** Reembolsos pendientes: compras rechazadas (venta_id) y reservas canceladas (reserva_id) que esperan la transferencia al cliente. */
  reembolsos = signal<ReembolsoDetalle[]>([]);
  errorReembolsos = signal<boolean>(false);

  totalPendientes = computed(() => this.pagos().length);
  montoTotalPendiente = computed(() => this.pagos().reduce((sum, p) => sum + p.monto, 0));

  private pollInterval: any = null;

  ngOnInit() {
    this.cargar();
    this.cargarReembolsos();
    this.pollInterval = setInterval(() => {
      this.cargar(true);
      this.cargarReembolsos();
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

  cargarReembolsos() {
    this.devolucionesService.reembolsos('pendiente').subscribe({
      next: (data) => {
        this.reembolsos.set(data || []);
        this.errorReembolsos.set(false);
      },
      error: () => this.errorReembolsos.set(true), // no impide trabajar con los pagos
    });
  }

  /** "Compra #41" o "Reserva #5": a qué pedido pertenece el reembolso. */
  etiquetaReembolso(r: ReembolsoDetalle): string {
    return r.venta_id != null ? `Compra #${r.venta_id}` : `Reserva #${r.reserva_id}`;
  }

  /** "Procesar Reembolso": el cajero ya le transfirió el dinero al cliente (al QR que subió desde la app). */
  procesarReembolso(r: ReembolsoDetalle) {
    const etiqueta = this.etiquetaReembolso(r);
    const monto = r.monto.toFixed(2);
    const mensaje = r.qr_devolucion_url
      ? `¿Ya le transferiste $${monto} al QR del cliente? La ${etiqueta.toLowerCase()} pasará a REEMBOLSADA.`
      : `El cliente todavía no subió su QR de devolución. ¿Marcar de todos modos la ${etiqueta.toLowerCase()} como REEMBOLSADA ($${monto})?`;
    if (!window.confirm(mensaje)) return;

    this.procesando.set(true);
    const origen = r.venta_id != null ? { venta_id: r.venta_id } : { reserva_id: r.reserva_id as number };
    this.devolucionesService.procesarReembolso(origen).subscribe({
      next: () => {
        this.procesando.set(false);
        this.mostrarToast(`Reembolso de la ${etiqueta.toLowerCase()} realizado`, false);
        this.cargarReembolsos();
      },
      error: (err) => {
        this.procesando.set(false);
        this.mostrarToast(err.error?.detail || 'No se pudo procesar el reembolso', true);
        this.cargarReembolsos();
      },
    });
  }

  /** Compra hecha sin conexión desde la app: se aprueba (descuenta el stock) o se rechaza (reembolso). */
  esCompraOffline(pago: Pago): boolean {
    return pago.estado === 'pendiente_verificacion';
  }

  /** "Aprobar Venta": descuenta el stock y completa la venta. Sin stock el servidor la cancela y deja el reembolso pendiente. */
  aprobarVenta(pago: Pago, event?: Event) {
    event?.stopPropagation();
    const montoTxt = pago.monto_formateado || `$${pago.monto.toFixed(2)}`;
    if (!window.confirm(`¿Aprobar la Venta #${pago.venta_id} (${montoTxt})? Se descontará el stock y la venta quedará completada.`)) return;

    this.procesando.set(true);
    this.pagosService.verificar(pago.id, 'APROBAR').subscribe({
      next: () => {
        this.procesando.set(false);
        this.cerrarDetalle();
        this.mostrarToast(`Venta #${pago.venta_id} aprobada: stock descontado`, false);
        this.cargar(true);
      },
      error: (err) => {
        this.procesando.set(false);
        this.mostrarToast(err.error?.detail || 'No se pudo aprobar la venta', true);
        this.cargar(true); // sin stock el servidor la cancela: ya no está pendiente
      },
    });
  }

  /** "Rechazar y Reembolsar": cancela la venta y crea el reembolso pendiente (el cliente adjunta su QR desde la app). */
  rechazarYReembolsar(pago: Pago, event?: Event) {
    event?.stopPropagation();
    const motivo = window.prompt(`Motivo del rechazo (Venta #${pago.venta_id}). Se cancelará la venta y quedará un reembolso pendiente para el cliente:`);
    if (motivo === null) return;

    this.procesando.set(true);
    this.pagosService.verificar(pago.id, 'RECHAZAR', motivo.trim() || undefined).subscribe({
      next: () => {
        this.procesando.set(false);
        this.cerrarDetalle();
        this.mostrarToast(`Venta #${pago.venta_id} rechazada. Quedó un reembolso pendiente para el cliente`, false);
        this.cargar(true);
      },
      error: (err) => {
        this.procesando.set(false);
        this.mostrarToast(err.error?.detail || 'No se pudo rechazar la venta', true);
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
