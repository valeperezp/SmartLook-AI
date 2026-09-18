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

@Component({
  selector: 'app-stripe-card',
  standalone: true,
  imports: [CommonModule, IconComponent],
  templateUrl: './stripe-card.html',
  styleUrl: './stripe-card.scss',
})
export class StripeCard implements OnInit, OnDestroy {
  @Input({ required: true }) ventaId!: number;
  @Input({ required: true }) monto!: number;

  @Output() pagoExitoso = new EventEmitter<void>();
  @Output() errorPago = new EventEmitter<string>();

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

    // Remover widgets flotantes residuales de Stripe si los hubiera
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
            const msg = err.error?.detail || 'Error al inicializar la pasarela de pago';
            this.errorMensaje.set(msg);
            this.errorPago.emit(msg);
          },
        });
    } catch (err: any) {
      this.cargandoStripe.set(false);
      const msg = err?.message || 'Error al conectar con Stripe';
      this.errorMensaje.set(msg);
      this.errorPago.emit(msg);
    }
  }

  private montarElemento(clientSecret: string) {
    if (!this.stripe) return;

    this.elements = this.stripe.elements({
      clientSecret,
      appearance: {
        theme: 'night',
        variables: {
          colorPrimary: '#b3714f',
          colorBackground: '#1e293b',
          colorText: '#f8fafc',
          colorDanger: '#ef4444',
          fontFamily: 'Plus Jakarta Sans, Inter, system-ui, sans-serif',
          borderRadius: '6px',
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

  async procesarPago() {
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
        const msg = error.message || 'El pago con tarjeta no pudo ser procesado';
        this.errorMensaje.set(msg);
        this.errorPago.emit(msg);
        return;
      }

      if (paymentIntent && paymentIntent.status === 'succeeded') {
        this.pagosService.confirmar(paymentIntent.id).subscribe({
          next: () => {
            this.procesandoPago.set(false);
            this.pagoExitoso.emit();
          },
          error: (err) => {
            this.procesandoPago.set(false);
            const msg =
              err.error?.detail ||
              'Pago procesado en Stripe pero ocurrió una incidencia al registrarlo en el sistema';
            this.errorMensaje.set(msg);
            this.errorPago.emit(msg);
          },
        });
      } else {
        this.procesandoPago.set(false);
        const msg = `Estado del pago: ${paymentIntent?.status || 'desconocido'}`;
        this.errorMensaje.set(msg);
        this.errorPago.emit(msg);
      }
    } catch (err: any) {
      this.procesandoPago.set(false);
      const msg = err?.message || 'Error inesperado al confirmar el pago en la pasarela';
      this.errorMensaje.set(msg);
      this.errorPago.emit(msg);
    }
  }
}
