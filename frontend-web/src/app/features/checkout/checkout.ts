import { Component, OnInit, inject, signal, computed } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';

import { CarritoService } from '../../core/services/carrito.service';
import { SucursalesService } from '../../core/services/sucursales.service';
import { VentasService } from '../../core/services/ventas.service';
import { AuthService } from '../../core/services/auth.service';

import { Sucursal } from '../../core/models/sucursal.model';
import { VentaOnlineCreate } from '../../core/models/venta.model';
import { IconComponent } from '../../core/components/icon/icon';
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
  ],
  templateUrl: './checkout.html',
  styleUrl: './checkout.scss',
})
export class Checkout implements OnInit {
  private router = inject(Router);
  carritoService = inject(CarritoService);
  private sucursalesService = inject(SucursalesService);
  private ventasService = inject(VentasService);
  auth = inject(AuthService);

  sucursales = signal<Sucursal[]>([]);
  cargandoSucursales = signal<boolean>(true);
  sucursalId = signal<number | null>(null);

  metodoPago = signal<'tarjeta' | 'qr'>('tarjeta');

  creandoVenta = signal<boolean>(false);
  errorCheckout = signal<string | null>(null);

  ventaId = signal<number | null>(null);
  montoVenta = signal<number>(0);

  pagoCompletado = signal<boolean>(false);
  pagoQREnviado = signal<boolean>(false);
  ordenFinalizadaId = signal<number | null>(null);

  sucursalSeleccionada = computed(() =>
    this.sucursales().find((s) => s.id === this.sucursalId())
  );

  ngOnInit() {
    // Si el carrito está vacío y no venimos de un pago ya completado o enviado, redirigir al carrito
    if (
      this.carritoService.estaVacio() &&
      !this.pagoCompletado() &&
      !this.pagoQREnviado()
    ) {
      this.router.navigate(['/carrito']);
      return;
    }

    this.cargarSucursales();
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
        this.cargandoSucursales.set(false);
        this.errorCheckout.set('No se pudieron cargar las sucursales disponibles.');
      },
    });
  }

  seleccionarMetodoPago(metodo: 'tarjeta' | 'qr') {
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

  onErrorPago(msg: string) {
    this.errorCheckout.set(msg);
  }

  cambiarSucursal() {
    this.ventaId.set(null);
    this.montoVenta.set(0);
    this.errorCheckout.set(null);
  }
}
