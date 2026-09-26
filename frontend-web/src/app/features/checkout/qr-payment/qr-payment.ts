import {
  Component,
  Input,
  Output,
  EventEmitter,
  OnInit,
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
  selector: 'app-qr-payment',
  standalone: true,
  imports: [CommonModule, IconComponent],
  templateUrl: './qr-payment.html',
  styleUrl: './qr-payment.scss',
})
export class QrPayment implements OnInit {
  @Input({ required: true }) ventaId!: number;
  @Input({ required: true }) monto!: number;
  @Input({ required: true }) sucursalId!: number;

  @Output() pagoEnviado = new EventEmitter<void>();

  private pagosService = inject(PagosService);
  private sucursalQRService = inject(SucursalQRService);

  cargando = signal<boolean>(true);
  pago = signal<Pago | null>(null);
  qrDataUrl = signal<string | null>(null);
  errorMensaje = signal<string | null>(null);

  // QR real de la sucursal (subido por el encargado) — es el que el cliente
  // tiene que escanear con su app bancaria para pagar. Se pide siempre fresco
  // al abrir esta pantalla, así que si el encargado subió uno nuevo, este es
  // el que se ve (no hay caché de por medio).
  qrSucursal = signal<SucursalQR | null>(null);
  cargandoQrSucursal = signal<boolean>(true);

  archivoSeleccionado = signal<File | null>(null);
  previewUrl = signal<string | null>(null);
  subiendoComprobante = signal<boolean>(false);

  async ngOnInit() {
    await this.iniciarPagoQR();
    this.cargarQrSucursal();
  }

  private cargarQrSucursal() {
    this.cargandoQrSucursal.set(true);
    this.sucursalQRService.obtener(this.sucursalId).subscribe({
      next: (qr) => {
        this.qrSucursal.set(qr);
        this.cargandoQrSucursal.set(false);
      },
      error: () => {
        // Sucursal sin QR configurado todavía, o error de red — no bloquea el
        // resto del flujo, el cliente igual puede subir el comprobante después.
        this.qrSucursal.set(null);
        this.cargandoQrSucursal.set(false);
      },
    });
  }

  async iniciarPagoQR() {
    this.cargando.set(true);
    this.errorMensaje.set(null);

    this.pagosService.crearPagoQR(this.ventaId).subscribe({
      next: async (pago) => {
        this.pago.set(pago);
        const url = `${window.location.origin}/pago/${pago.id}/comprobante`;

        try {
          const dataUrl = await QRCode.toDataURL(url, {
            width: 240,
            margin: 1,
            color: {
              dark: '#1e293b',
              light: '#ffffff',
            },
          });
          this.qrDataUrl.set(dataUrl);
        } catch (e) {
          console.error('Error generando QR', e);
        }

        this.cargando.set(false);
      },
      error: (err) => {
        this.cargando.set(false);
        const msg =
          err.error?.detail || 'No se pudo generar la solicitud de pago QR.';
        this.errorMensaje.set(msg);
      },
    });
  }

  onFileSelected(event: Event) {
    const input = event.target as HTMLInputElement;
    if (!input.files || input.files.length === 0) return;

    const file = input.files[0];
    if (!file.type.startsWith('image/')) {
      this.errorMensaje.set(
        'Por favor seleccioná un archivo de imagen válido (PNG, JPG, WEBP).'
      );
      return;
    }

    if (file.size > 10 * 1024 * 1024) {
      this.errorMensaje.set('El archivo supera el límite de 10 MB.');
      return;
    }

    this.errorMensaje.set(null);
    this.archivoSeleccionado.set(file);

    if (this.previewUrl()) {
      URL.revokeObjectURL(this.previewUrl()!);
    }
    this.previewUrl.set(URL.createObjectURL(file));
  }

  removerArchivo(fileInput: HTMLInputElement) {
    if (this.previewUrl()) {
      URL.revokeObjectURL(this.previewUrl()!);
    }
    this.archivoSeleccionado.set(null);
    this.previewUrl.set(null);
    fileInput.value = '';
  }

  subirComprobante() {
    const currentPago = this.pago();
    const file = this.archivoSeleccionado();

    if (!currentPago || !file) {
      this.errorMensaje.set(
        'Debes seleccionar una imagen del comprobante antes de enviarlo.'
      );
      return;
    }

    this.subiendoComprobante.set(true);
    this.errorMensaje.set(null);

    this.pagosService.subirComprobante(currentPago.id, file).subscribe({
      next: () => {
        this.subiendoComprobante.set(false);
        this.pagoEnviado.emit();
      },
      error: (err) => {
        this.subiendoComprobante.set(false);
        const msg =
          err.error?.detail ||
          'Error al subir el comprobante. Intentá nuevamente.';
        this.errorMensaje.set(msg);
      },
    });
  }
}
