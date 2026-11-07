import { Component, OnInit, inject, signal, computed } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';

import { CarritoService } from '../../core/services/carrito.service';
import { SucursalesService } from '../../core/services/sucursales.service';
import { VentasService } from '../../core/services/ventas.service';
import { AuthService } from '../../core/services/auth.service';
import { PagosService } from '../../core/services/pagos.service';
import { OfflineSyncService } from '../../core/services/offline-sync.service';
import { FidelizacionService } from '../../core/services/fidelizacion.service';
import { MisPuntos } from '../../core/models/fidelizacion.model';

import { Sucursal } from '../../core/models/sucursal.model';
import { VentaOnlineCreate } from '../../core/models/venta.model';
import { IconComponent } from '../../core/components/icon/icon';
import { OfflineBanner } from '../../core/components/offline-banner/offline-banner';
import { StripeCard } from './stripe-card/stripe-card';
import { QrPayment } from './qr-payment/qr-payment';

@Component({
  selector: 'app-checkout',
  standalone: true,
  imports: [
    CommonModule,
    FormsModule,
    RouterLink,
    IconComponent,
    StripeCard,
    QrPayment,
    OfflineBanner,
  ],
  templateUrl: './checkout.html',
  styleUrl: './checkout.scss',
})
export class Checkout implements OnInit {
  private router = inject(Router);
  carritoService = inject(CarritoService);
  private sucursalesService = inject(SucursalesService);
  private ventasService = inject(VentasService);
  private pagosService = inject(PagosService);
  private fidelizacionService = inject(FidelizacionService);
  auth = inject(AuthService);
  /** Modo offline: estado de la red y operaciones pendientes (IndexedDB). */
  offline = inject(OfflineSyncService);

  sucursales = signal<Sucursal[]>([]);
  cargandoSucursales = signal<boolean>(true);
  sucursalId = signal<number | null>(null);

  metodoPago = signal<'tarjeta' | 'qr' | 'efectivo'>('tarjeta');

  creandoVenta = signal<boolean>(false);
  errorCheckout = signal<string | null>(null);

  ventaId = signal<number | null>(null);
  montoVenta = signal<number>(0);

  pagoCompletado = signal<boolean>(false);
  pagoQREnviado = signal<boolean>(false);
  pagoEfectivoConfirmado = signal<boolean>(false);
  confirmandoEfectivo = signal<boolean>(false);
  ordenFinalizadaId = signal<number | null>(null);
  /** Sin conexión: la reserva quedó guardada en el dispositivo y se confirmará al volver la red. */
  reservaGuardadaOffline = signal<boolean>(false);

  sucursalSeleccionada = computed(() =>
    this.sucursales().find((s) => s.id === this.sucursalId())
  );

  // ---------- Puntos de fidelización (CU17): canje como descuento ----------
  /** Saldo y regla de la empresa (vienen del backend). Null si no es un cliente, no hay red o el servidor no respondió. */
  misPuntos = signal<MisPuntos | null>(null);
  usarPuntos = signal<boolean>(false);

  /** Puntos que se pueden canjear: todos los que tiene, sin que el descuento supere el total de la compra. */
  puntosUsables = computed(() => {
    const p = this.misPuntos();
    if (!p || p.saldo <= 0 || p.valor_punto_centavos <= 0) return 0;
    const totalCentavos = Math.round(this.carritoService.total() * 100);
    return Math.max(0, Math.min(p.saldo, Math.floor(totalCentavos / p.valor_punto_centavos)));
  });
  /** Puntos que realmente se canjean (0 si el cliente no marcó la casilla). */
  puntosACanjear = computed(() => (this.usarPuntos() ? this.puntosUsables() : 0));
  /** Descuento en moneda de lo que se canjearía con todos los puntos usables (lo que muestra la casilla). */
  descuentoPosible = computed(() => ((this.misPuntos()?.valor_punto_centavos ?? 0) * this.puntosUsables()) / 100);
  descuentoPuntos = computed(() => ((this.misPuntos()?.valor_punto_centavos ?? 0) * this.puntosACanjear()) / 100);
  /** Lo que paga el cliente: el total del carrito menos el descuento por puntos (baja en tiempo real al marcar la casilla). */
  totalAPagar = computed(() => Math.max(0, Math.round((this.carritoService.total() - this.descuentoPuntos()) * 100) / 100));

  ngOnInit() {
    // Si el carrito está vacío y no venimos de un pago ya completado o enviado, redirigir al carrito
    if (
      this.carritoService.estaVacio() &&
      !this.pagoCompletado() &&
      !this.pagoQREnviado() &&
      !this.pagoEfectivoConfirmado()
    ) {
      this.router.navigate(['/carrito']);
      return;
    }

    this.cargarSucursales();
    this.cargarPuntos();
  }

  /** Pide el saldo y la regla al backend. Sin red o sin sesión de cliente simplemente no se ofrece el canje. */
  private cargarPuntos() {
    if (!this.auth.isCliente() || navigator.onLine === false) return;
    this.fidelizacionService.misPuntos().subscribe({
      next: (p) => this.misPuntos.set(p),
      error: () => this.misPuntos.set(null),
    });
  }

  cargarSucursales() {
    this.cargandoSucursales.set(true);
    this.sucursalesService.listar().subscribe({
      next: (list) => {
        const activas = list.filter((s) => s.activa);
        this.sucursales.set(activas);
        if (activas.length > 0 && !this.sucursalId()) {
          this.sucursalId.set(activas[0].id);
        }
        this.cargandoSucursales.set(false);
      },
      error: () => {
        // Sin servidor: sucursales del catálogo descargado para offline (para poder dejar la reserva guardada)
        void this.offline.leerCatalogoLocal().then((local) => {
          this.cargandoSucursales.set(false);
          if (local && local.sucursales.length > 0) {
            this.sucursales.set(local.sucursales);
            if (!this.sucursalId()) this.sucursalId.set(local.sucursales[0].id);
            return;
          }
          this.errorCheckout.set(
            navigator.onLine === false
              ? 'Sin conexión y sin catálogo guardado: descárgalo con conexión desde el catálogo ("Descargar catálogo para Offline") para poder reservar sin red.'
              : 'No se pudieron cargar las sucursales disponibles.',
          );
        });
      },
    });
  }

  seleccionarMetodoPago(metodo: 'tarjeta' | 'qr' | 'efectivo') {
    this.metodoPago.set(metodo);
  }

  iniciarPago() {
    if (!this.sucursalId()) {
      this.errorCheckout.set('Por favor seleccioná una sucursal para continuar.');
      return;
    }

    if (this.carritoService.estaVacio()) {
      this.router.navigate(['/carrito']);
      return;
    }

    if (navigator.onLine === false) {
      void this.guardarReservaSinConexion();
      return;
    }

    this.creandoVenta.set(true);
    this.errorCheckout.set(null);

    const payload: VentaOnlineCreate = {
      sucursal_id: this.sucursalId()!,
      items: this.carritoService.items().map((it) => ({
        producto_id: it.productoId,
        talla_id: it.tallaId,
        color_id: it.colorId,
        cantidad: it.cantidad,
      })),
      ...(this.puntosACanjear() > 0 ? { puntos_a_canjear: this.puntosACanjear() } : {}),
    };

    this.ventasService.crearVentaOnline(payload).subscribe({
      next: (venta) => {
        this.creandoVenta.set(false);
        this.ventaId.set(venta.id);
        this.montoVenta.set(venta.total);
      },
      error: (err) => {
        this.creandoVenta.set(false);
        const msg =
          err.error?.detail ||
          'Ocurrió un error al registrar la orden online. Intenta nuevamente.';
        this.errorCheckout.set(msg);
      },
    });
  }

  /**
   * Sin conexión no se puede pagar (Stripe/QR necesitan red): el pedido se guarda como una RESERVA del cliente en IndexedDB
   * (con su uuid) y se enviará sola a `POST /sync/operaciones` al volver la conexión. La prenda se paga al retirarla.
   * El carrito se vacía solo si la reserva se guardó; si falla, se conserva para no perder el pedido.
   */
  private async guardarReservaSinConexion() {
    const cliente = this.auth.currentUser();
    if (!cliente || !this.auth.isCliente()) {
      this.errorCheckout.set('Solo un cliente con sesión iniciada puede guardar una reserva sin conexión.');
      return;
    }
    this.creandoVenta.set(true);
    this.errorCheckout.set(null);
    try {
      await this.offline.registrarOperacion({
        tipo_operacion: 'RESERVA_CLIENTE',
        sucursal_id: this.sucursalId()!,
        cliente_id: cliente.id,
        items: this.carritoService.items().map((it) => ({
          producto_id: it.productoId,
          talla_id: it.tallaId,
          color_id: it.colorId,
          nombre_producto: it.nombreProducto,
          cantidad: it.cantidad,
          precio_unitario_centavos: Math.round(it.precio * 100),
        })),
      });
      this.carritoService.vaciar();
      this.reservaGuardadaOffline.set(true);
    } catch (error) {
      this.errorCheckout.set(error instanceof Error ? error.message : 'No se pudo guardar la reserva en este dispositivo.');
    } finally {
      this.creandoVenta.set(false);
    }
  }

  iniciarPagoConTarjeta() {
    this.iniciarPago();
  }

  onPagoExitoso() {
    const ordenId = this.ventaId();
    this.ordenFinalizadaId.set(ordenId);
    this.pagoCompletado.set(true);
    this.carritoService.vaciar();
  }

  onPagoQREnviado() {
    const ordenId = this.ventaId();
    this.ordenFinalizadaId.set(ordenId);
    this.pagoQREnviado.set(true);
    this.carritoService.vaciar();
  }

  confirmarPagoEfectivo() {
    const venta = this.ventaId();
    if (!venta) return;

    this.confirmandoEfectivo.set(true);
    this.errorCheckout.set(null);

    this.pagosService.crearPagoEfectivo(venta).subscribe({
      next: () => {
        this.confirmandoEfectivo.set(false);
        this.ordenFinalizadaId.set(venta);
        this.pagoEfectivoConfirmado.set(true);
        this.carritoService.vaciar();
      },
      error: (err) => {
        this.confirmandoEfectivo.set(false);
        const msg =
          err.error?.detail || 'No se pudo registrar el pago en efectivo. Intentá nuevamente.';
        this.errorCheckout.set(msg);
      },
    });
  }

  onErrorPago(msg: string) {
    this.errorCheckout.set(msg);
  }

  cambiarSucursal() {
    this.ventaId.set(null);
    this.montoVenta.set(0);
    this.errorCheckout.set(null);
  }
}
