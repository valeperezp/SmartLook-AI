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
import { loadStripe, Stripe, StripeElements } from '@stripe/stripe-js';
import { environment } from '../../../../environments/environment';
import { PagosService } from '../../../core/services/pagos.service';
import { IconComponent } from '../../../core/components/icon/icon';

/**
 * Modal de cobro con pasarela de pago Stripe (CU19).
 * Cuenta con estructura de 3 secciones (header fijo, body scrolleable y footer fijo)
 * para garantizar accesibilidad del botón de confirmación en cualquier resolución.
 */
@Component({
  selector: 'app-pago-modal',
  standalone: true,
  imports: [CommonModule, IconComponent],
  templateUrl: './pago-modal.html',
  styleUrl: './pago-modal.scss',
})
export class PagoModal implements OnInit, OnDestroy {
  @Input({ required: true }) ventaId!: number;
  @Input({ required: true }) monto!: number;
  @Input() nombreCliente: string | null = null;

  @Output() cerrar = new EventEmitter<boolean>();

  private pagosService = inject(PagosService);

  private stripe: Stripe | null = null;
  private elements: StripeElements | null = null;
  private paymentElement: any = null;
  private paymentIntentId: string | null = null;

  cargandoStripe = signal<boolean>(true);
  stripeListo = signal<boolean>(false);
  procesandoPago = signal<boolean>(false);
  errorMensaje = signal<string | null>(null);

  async ngOnInit() {
    await this.inicializarStripe();
  }

  ngOnDestroy() {
    this.limpiarElementos();
  }

  private limpiarElementos() {
    if (this.paymentElement) {
      try {
        this.paymentElement.unmount();
        this.paymentElement.destroy();
      } catch {
        // ignore
      }
      this.paymentElement = null;
    }
    this.elements = null;
    this.stripe = null;

    // Remover cualquier widget flotante residual de Stripe inyectado en el DOM
    try {
      const widgets = document.querySelectorAll(
        '[class*="stripe-assistant"], [id*="stripe-assistant"], iframe[name*="assistant"], iframe[title*="assistant" i]'
      );
      widgets.forEach((el) => el.remove());
    } catch {
      // ignore
    }
  }

  private async inicializarStripe() {
    this.cargandoStripe.set(true);
    this.errorMensaje.set(null);

    try {
      this.stripe = await loadStripe(environment.stripePublishableKey, {
        developerTools: {
          assistant: {
            enabled: false,
          },
        },
      });
      if (!this.stripe) {
        throw new Error('No se pudo cargar la librería de Stripe');
      }

      this.pagosService
        .crearIntent({ venta_id: this.ventaId, metodo: 'tarjeta' })
        .subscribe({
          next: (res) => {
            this.paymentIntentId = res.payment_intent_id;
            this.montarElemento(res.client_secret);
          },
          error: (err) => {
            this.cargandoStripe.set(false);
            const msg = err.error?.detail || 'Error al inicializar el PaymentIntent';
            this.errorMensaje.set(msg);
          },
        });
    } catch (err: any) {
      this.cargandoStripe.set(false);
      this.errorMensaje.set(err?.message || 'Error al conectar con Stripe');
    }
  }

  private montarElemento(clientSecret: string) {
    if (!this.stripe) return;

    this.elements = this.stripe.elements({
      clientSecret,
      appearance: {
        theme: 'night',
        variables: {
          colorPrimary: '#6366f1',
          colorBackground: '#1e293b',
          colorText: '#f8fafc',
          colorDanger: '#ef4444',
          fontFamily: 'Inter, system-ui, sans-serif',
          borderRadius: '8px',
        },
      },
    });

    this.paymentElement = this.elements.create('payment');
    this.paymentElement.mount('#payment-element');

    this.paymentElement.on('ready', () => {
      this.cargandoStripe.set(false);
      this.stripeListo.set(true);
    });

    this.paymentElement.on('change', (event: any) => {
      if (event.complete) {
        this.errorMensaje.set(null);
      }
    });
  }


  async confirmarPago() {
    if (!this.stripe || !this.elements || !this.paymentIntentId) return;

    this.procesandoPago.set(true);
    this.errorMensaje.set(null);

    try {
      const { error, paymentIntent } = await this.stripe.confirmPayment({
        elements: this.elements,
        redirect: 'if_required',
      });

      if (error) {
        this.procesandoPago.set(false);
        this.errorMensaje.set(error.message || 'El pago no pudo ser procesado');
        return;
      }

      if (paymentIntent && paymentIntent.status === 'succeeded') {
        // Confirmar en el backend para registrar el modelo Pago
        this.pagosService.confirmar(paymentIntent.id).subscribe({
          next: () => {
            this.procesandoPago.set(false);
            this.cerrar.emit(true);
          },
          error: (err) => {
            this.procesandoPago.set(false);
            const msg = err.error?.detail || 'Pago completado en Stripe pero falló el registro en BD';
            this.errorMensaje.set(msg);
            this.cerrar.emit(true);
          },
        });
      } else {
        this.procesandoPago.set(false);
        this.errorMensaje.set(`Estado del pago: ${paymentIntent?.status || 'desconocido'}`);
      }
    } catch (err: any) {
      this.procesandoPago.set(false);
      this.errorMensaje.set(err?.message || 'Error inesperado al confirmar el pago');
    }
  }

  cancelar() {
    if (this.procesandoPago()) return;
    this.cerrar.emit(false);
  }
}
