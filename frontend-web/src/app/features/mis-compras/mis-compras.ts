import { Component, OnInit, inject, signal, computed } from '@angular/core';
import { CommonModule, DatePipe } from '@angular/common';
import { RouterLink } from '@angular/router';
import { VentasService } from '../../core/services/ventas.service';
import { PagosService } from '../../core/services/pagos.service';
import { AuthService } from '../../core/services/auth.service';
import { Venta } from '../../core/models/venta.model';
import { Pago } from '../../core/models/pago.model';
import { IconComponent } from '../../core/components/icon/icon';

export interface CompraViewModel {
  venta: Venta;
  pago?: Pago;
  cargandoPago: boolean;
}

@Component({
  selector: 'app-mis-compras',
  standalone: true,
  imports: [CommonModule, DatePipe, RouterLink, IconComponent],
  templateUrl: './mis-compras.html',
  styleUrl: './mis-compras.scss',
})
export class MisCompras implements OnInit {
  private ventasService = inject(VentasService);
  private pagosService = inject(PagosService);
  auth = inject(AuthService);

  compras = signal<CompraViewModel[]>([]);
  cargando = signal<boolean>(true);
  errorCarga = signal<string | null>(null);

  compraSeleccionada = signal<CompraViewModel | null>(null);
  modalDetalleAbierto = signal<boolean>(false);

  totalCompras = computed(() => this.compras().length);

  ngOnInit() {
    this.cargarCompras();
  }

  cargarCompras() {
    this.cargando.set(true);
    this.errorCarga.set(null);

    this.ventasService.listarMisCompras().subscribe({
      next: (ventas) => {
        const items: CompraViewModel[] = ventas.map((v) => ({
          venta: v,
          cargandoPago: true,
        }));
        this.compras.set(items);
        this.cargando.set(false);

        // Cargar detalles de pago para cada venta
        items.forEach((item, index) => {
          this.pagosService.obtenerPagoDeVenta(item.venta.id).subscribe({
            next: (pagos) => {
              const pagoPrincipal = pagos.find((p) => p.metodo === 'qr') || pagos[0];
              this.compras.update((current) => {
                const copy = [...current];
                if (copy[index]) {
                  copy[index] = {
                    ...copy[index],
                    pago: pagoPrincipal,
                    cargandoPago: false,
                  };
                }
                return copy;
              });
            },
            error: () => {
              this.compras.update((current) => {
                const copy = [...current];
                if (copy[index]) {
                  copy[index] = {
                    ...copy[index],
                    cargandoPago: false,
                  };
                }
                return copy;
              });
            },
          });
        });
      },
      error: (err) => {
        this.cargando.set(false);
        const msg = err.error?.detail || 'No se pudieron cargar tus compras.';
        this.errorCarga.set(msg);
      },
    });
  }

  abrirDetalle(compra: CompraViewModel) {
    this.compraSeleccionada.set(compra);
    this.modalDetalleAbierto.set(true);
  }

  cerrarDetalle() {
    this.modalDetalleAbierto.set(false);
    this.compraSeleccionada.set(null);
  }

  obtenerMotivoRechazo(pago?: Pago): string | null {
    if (!pago || pago.estado !== 'fallido' || !pago.referencia_externa) return null;
    return pago.referencia_externa.replace(/^RECHAZADO:\s*/i, '').trim();
  }

  verComprobante(pago?: Pago, event?: Event) {
    if (event) event.stopPropagation();
    if (pago?.comprobante_url) {
      window.open(pago.comprobante_url, '_blank');
    }
  }
}
