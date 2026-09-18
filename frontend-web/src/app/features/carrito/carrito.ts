import { Component, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterLink, Router } from '@angular/router';
import { CarritoService } from '../../core/services/carrito.service';
import { IconComponent } from '../../core/components/icon/icon';

@Component({
  selector: 'app-carrito',
  standalone: true,
  imports: [CommonModule, RouterLink, IconComponent],
  templateUrl: './carrito.html',
  styleUrl: './carrito.scss',
})
export class Carrito {
  carritoService = inject(CarritoService);
  private router = inject(Router);

  incrementar(index: number) {
    const item = this.carritoService.items()[index];
    if (!item) return;
    this.carritoService.actualizarCantidad(index, item.cantidad + 1);
  }

  decrementar(index: number) {
    const item = this.carritoService.items()[index];
    if (!item) return;
    this.carritoService.actualizarCantidad(index, item.cantidad - 1);
  }

  eliminar(index: number) {
    this.carritoService.eliminar(index);
  }

  vaciar() {
    this.carritoService.vaciar();
  }

  irAlCheckout() {
    this.router.navigate(['/checkout']);
  }
}
