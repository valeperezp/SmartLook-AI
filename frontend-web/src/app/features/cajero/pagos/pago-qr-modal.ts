import {
  Component,
  Input,
  Output,
  EventEmitter,
  OnInit,
  OnDestroy,
  inject,
  signal,
} from '@angular/core';
import { CommonModule } from '@angular/common';
import * as QRCode from 'qrcode';
import { PagosService } from '../../../core/services/pagos.service';
import { SucursalQRService } from '../../../core/services/sucursal-qr.service';
import { Pago } from '../../../core/models/pago.model';
import { SucursalQR } from '../../../core/models/sucursal-qr.model';
import { IconComponent } from '../../../core/components/icon/icon';

@Component({
  selector: 'app-pago-qr-modal',
  standalone: true,
  imports: [CommonModule, IconComponent],
  templateUrl: './pago-qr-modal.html',
  styleUrl: './pago-qr-modal.scss',
})
export class PagoQRModal implements OnInit, OnDestroy {
  @Input({ required: true }) ventaId!: number;
  @Input({ required: true }) sucursalId!: number;
  @Input({ required: true }) monto!: number;

  @Output() cerrar = new EventEmitter<boolean>();

  private pagosService = inject(PagosService);
  private sucursalQRService = inject(SucursalQRService);

  pagoQR = signal<Pago | null>(null);
  qrSucursal = signal<SucursalQR | null>(null);
  qrComprobanteDataUrl = signal<string | null>(null);
  publicUrl = signal<string>('');

  cargando = signal<boolean>(true);
  esperandoComprobante = signal<boolean>(false);
  comprobanteRecibido = signal<boolean>(false);
  procesando = signal<boolean>(false);
  errorMensaje = signal<string | null>(null);

  toast = signal<string | null>(null);
  toastIsError = signal<boolean>(false);

  private pollInterval: any = null;

  async ngOnInit() {
    await this.iniciarCobroQR();
  }

  ngOnDestroy() {
    this.detenerPolling();
  }

  async iniciarCobroQR() {
    this.cargando.set(true);
    this.errorMensaje.set(null);

    this.pagosService.crearPagoQR(this.ventaId).subscribe({
      next: async (pago) => {
        this.pagoQR.set(pago);

        const url = `${window.location.origin}/pago/${pago.id}/comprobante`;
        this.publicUrl.set(url);
        try {
          const dataUrl = await QRCode.toDataURL(url, {
            width: 220,
            margin: 1,
            color: {
              dark: '#000000',
              light: '#ffffff',
            },
          });
          this.qrComprobanteDataUrl.set(dataUrl);
        } catch (e) {
          console.error('Error generando QR de comprobante', e);
        }

        this.sucursalQRService.obtener(this.sucursalId).subscribe({
          next: (sqr) => this.qrSucursal.set(sqr),
          error: (err) => {
            if (err.status !== 404) {
              console.error('Error cargando QR sucursal', err);
            }
          },
        });

        this.cargando.set(false);
        this.esperandoComprobante.set(true);
        this.iniciarPolling(pago.id);
      },
      error: (err) => {
        this.cargando.set(false);
        const msg = err.error?.detail || 'Error al crear el pago QR';
        this.errorMensaje.set(msg);
      },
    });
  }

  private iniciarPolling(pagoId: number) {
    this.detenerPolling();
    this.pollInterval = setInterval(() => {
      this.pagosService.obtenerPago(pagoId).subscribe({
        next: (pago) => {
          this.pagoQR.set(pago);
          if (pago.comprobante_path) {
            this.comprobanteRecibido.set(true);
            this.esperandoComprobante.set(false);
            this.detenerPolling();
          }
        },
        error: (err) => console.error('Error en polling de pago QR', err),
      });
    }, 3000);
  }

  private detenerPolling() {
    if (this.pollInterval) {
      clearInterval(this.pollInterval);
      this.pollInterval = null;
    }
  }

  verComprobante() {
    const pago = this.pagoQR();
    if (pago?.comprobante_url) {
      window.open(pago.comprobante_url, '_blank');
    }
  }

  confirmarPago() {
    const pago = this.pagoQR();
    if (!pago) return;

    this.procesando.set(true);
    this.pagosService.confirmarPagoQR(pago.id, true).subscribe({
      next: () => {
        this.procesando.set(false);
        this.mostrarToast('¡Pago QR confirmado exitosamente!');
        setTimeout(() => {
          this.cerrar.emit(true);
        }, 1000);
      },
      error: (err) => {
        this.procesando.set(false);
        const msg = err.error?.detail || 'Error al confirmar el pago QR';
        this.mostrarToast(msg, true);
      },
    });
  }

  rechazarPago() {
    const pago = this.pagoQR();
    if (!pago) return;

    const motivo = window.prompt('Ingresá el motivo del rechazo del comprobante:');
    if (motivo === null) return;

    this.procesando.set(true);
    this.pagosService.confirmarPagoQR(pago.id, false, motivo).subscribe({
      next: () => {
        this.procesando.set(false);
        this.mostrarToast('Pago QR rechazado');
        setTimeout(() => {
          this.cerrar.emit(false);
        }, 1000);
      },
      error: (err) => {
        this.procesando.set(false);
        const msg = err.error?.detail || 'Error al rechazar el pago QR';
        this.mostrarToast(msg, true);
      },
    });
  }

  cancelar() {
    this.detenerPolling();
    this.cerrar.emit(false);
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
