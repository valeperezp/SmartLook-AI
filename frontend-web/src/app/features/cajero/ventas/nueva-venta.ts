import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { CatalogoService } from '../../../core/services/catalogo.service';
import { VentasService } from '../../../core/services/ventas.service';
import { PagosService } from '../../../core/services/pagos.service';
import { AuthService } from '../../../core/services/auth.service';
import { Categoria, DisponibilidadTallaColor, Producto } from '../../../core/models/catalogo.model';
import { Venta, VentaPresencialCreate } from '../../../core/models/venta.model';
import { Pago } from '../../../core/models/pago.model';
import { IconComponent } from '../../../core/components/icon/icon';
import { PagoModal } from '../pagos/pago-modal';
import { PagoQRModal } from '../pagos/pago-qr-modal';

export interface ItemCarrito {
  productoId: number;
  nombreProducto: string;
  precio: number;
  tallaId: number | null;
  nombreTalla: string | null;
  colorId: number | null;
  nombreColor: string | null;
  cantidad: number;
}

@Component({
  selector: 'app-nueva-venta',
  standalone: true,
  imports: [CommonModule, FormsModule, IconComponent, PagoModal, PagoQRModal],
  templateUrl: './nueva-venta.html',
  styleUrl: './nueva-venta.scss',
})
export class NuevaVenta implements OnInit {
  private catalogoService = inject(CatalogoService);
  private ventasService = inject(VentasService);
  private pagosService = inject(PagosService);
  auth = inject(AuthService);

  user = this.auth.currentUser;

  // Estado con signals
  productos = signal<Producto[]>([]);
  categorias = signal<Categoria[]>([]);
  carrito = signal<ItemCarrito[]>([]);
  busqueda = signal<string>('');
  categoriaSeleccionada = signal<number | null>(null);
  clienteId = signal<number | null>(null);
  procesando = signal<boolean>(false);
  cargandoProductos = signal<boolean>(true);
  toast = signal<string | null>(null);
  toastError = signal<boolean>(false);

  // Modal selector de variantes
  modalVarianteAbierto = signal<boolean>(false);
  productoParaAgregar = signal<Producto | null>(null);
  variantesDisponibles = signal<DisponibilidadTallaColor[]>([]);
  varianteSeleccionada = signal<DisponibilidadTallaColor | null>(null);
  cantidadParaAgregar = signal<number>(1);
  cargandoVariantes = signal<boolean>(false);

  // Modal ticket de venta
  ticketVenta = signal<Venta | null>(null);
  mostrarModalPago = signal<boolean>(false);
  mostrarModalPagoQR = signal<boolean>(false);
  pagosTicket = signal<Pago[]>([]);
  cargandoPagos = signal<boolean>(false);

  // Computed signals
  productosFiltrados = computed(() => {
    const q = this.busqueda().toLowerCase().trim();
    const catId = this.categoriaSeleccionada();

    return this.productos().filter((p) => {
      const matchCat = catId === null || p.categoria_id === catId;
      const matchQuery =
        !q ||
        p.nombre.toLowerCase().includes(q) ||
        (p.descripcion && p.descripcion.toLowerCase().includes(q));
      return matchCat && matchQuery;
    });
  });

  totalCarrito = computed(() => {
    return this.carrito().reduce((acc, item) => acc + item.precio * item.cantidad, 0);
  });

  unidadesCarrito = computed(() => {
    return this.carrito().reduce((acc, item) => acc + item.cantidad, 0);
  });

  ngOnInit() {
    this.cargarCategorias();
    this.cargarProductos();
  }

  cargarCategorias() {
    this.catalogoService.listarCategorias().subscribe({
      next: (cats) => this.categorias.set(cats.filter((c) => c.activo)),
      error: () => this.mostrarToast('Error al cargar categorías', true),
    });
  }

  cargarProductos() {
    this.cargandoProductos.set(true);
    const sucursalId = this.user()?.sucursal_id || undefined;
    this.catalogoService.listarProductos(false, sucursalId).subscribe({
      next: (prods) => {
        this.productos.set(prods);
        this.cargandoProductos.set(false);
      },
      error: () => {
        this.cargandoProductos.set(false);
        this.mostrarToast('Error al cargar catálogo de productos', true);
      },
    });
  }

  abrirSelectorVariante(prod: Producto) {
    this.productoParaAgregar.set(prod);
    this.cantidadParaAgregar.set(1);
    this.varianteSeleccionada.set(null);
    this.variantesDisponibles.set([]);
    this.cargandoVariantes.set(true);
    this.modalVarianteAbierto.set(true);

    const sucursalId = this.user()?.sucursal_id || 1;
    this.catalogoService.obtenerDisponibilidad(prod.id).subscribe({
      next: (disp) => {
        this.cargandoVariantes.set(false);
        const suc = disp.disponibilidad.find((s) => s.sucursal_id === sucursalId);
        if (suc && suc.items && suc.items.length > 0) {
          const conStock = suc.items.filter((i) => i.cantidad_disponible > 0);
          this.variantesDisponibles.set(conStock);
          if (conStock.length > 0) {
            this.varianteSeleccionada.set(conStock[0]);
          }
        } else {
          this.variantesDisponibles.set([]);
        }
      },
      error: () => {
        this.cargandoVariantes.set(false);
        this.mostrarToast('No se pudo verificar el stock del producto', true);
      },
    });
  }

  cerrarModalVariante() {
    this.modalVarianteAbierto.set(false);
    this.productoParaAgregar.set(null);
    this.varianteSeleccionada.set(null);
  }

  agregarAlCarrito() {
    const prod = this.productoParaAgregar();
    const v = this.varianteSeleccionada();
    const cant = this.cantidadParaAgregar();

    if (!prod) return;

    if (!v && this.variantesDisponibles().length > 0) {
      this.mostrarToast('Seleccioná una talla y color', true);
      return;
    }

    if (v && cant > v.cantidad_disponible) {
      this.mostrarToast(`Stock máximo disponible: ${v.cantidad_disponible}`, true);
      return;
    }

    const itemExistenteIndex = this.carrito().findIndex(
      (item) =>
        item.productoId === prod.id &&
        item.tallaId === (v?.talla_id || null) &&
        item.colorId === (v?.color_id || null)
    );

    if (itemExistenteIndex > -1) {
      const items = [...this.carrito()];
      items[itemExistenteIndex].cantidad += cant;
      this.carrito.set(items);
    } else {
      const nuevoItem: ItemCarrito = {
        productoId: prod.id,
        nombreProducto: prod.nombre,
        precio: prod.precio,
        tallaId: v?.talla_id || null,
        nombreTalla: v?.nombre_talla || null,
        colorId: v?.color_id || null,
        nombreColor: v?.nombre_color || null,
        cantidad: cant,
      };
      this.carrito.update((prev) => [...prev, nuevoItem]);
    }

    this.mostrarToast(`Agregado: ${prod.nombre} x${cant}`);
    this.cerrarModalVariante();
  }

  decrementarCantidad() {
    this.cantidadParaAgregar.update((c) => Math.max(1, c - 1));
  }

  incrementarCantidad() {
    const v = this.varianteSeleccionada();
    const max = v ? v.cantidad_disponible : 999;
    this.cantidadParaAgregar.update((c) => Math.min(max, c + 1));
  }

  actualizarCantidadItem(index: number, delta: number) {
    const items = [...this.carrito()];
    const nuevaCant = items[index].cantidad + delta;
    if (nuevaCant <= 0) {
      this.eliminarItemCarrito(index);
    } else {
      items[index].cantidad = nuevaCant;
      this.carrito.set(items);
    }
  }

  eliminarItemCarrito(index: number) {
    this.carrito.update((prev) => prev.filter((_, i) => i !== index));
  }

  vaciarCarrito() {
    this.carrito.set([]);
  }

  cobrar() {
    if (this.carrito().length === 0) {
      this.mostrarToast('El carrito está vacío', true);
      return;
    }

    const sucursalId = this.user()?.sucursal_id || 1;

    const payload: VentaPresencialCreate = {
      sucursal_id: sucursalId,
      cliente_id: this.clienteId() ? Number(this.clienteId()) : null,
      items: this.carrito().map((item) => ({
        producto_id: item.productoId,
        talla_id: item.tallaId,
        color_id: item.colorId,
        cantidad: item.cantidad,
      })),
    };

    this.procesando.set(true);
    this.ventasService.crearVentaPresencial(payload).subscribe({
      next: (venta) => {
        this.procesando.set(false);
        this.ticketVenta.set(venta);
        this.vaciarCarrito();
        this.clienteId.set(null);
        this.cargarProductos();
        this.cargarPagosTicket(venta.id);
      },
      error: (err) => {
        this.procesando.set(false);
        const mensaje = err.error?.detail || 'Error al procesar la venta en el servidor';
        this.mostrarToast(mensaje, true);
      },
    });
  }

  cargarPagosTicket(ventaId: number) {
    this.cargandoPagos.set(true);
    this.pagosService.listarPorVenta(ventaId).subscribe({
      next: (pagos) => {
        this.pagosTicket.set(pagos);
        this.cargandoPagos.set(false);
      },
      error: () => {
        this.cargandoPagos.set(false);
      },
    });
  }

  abrirPagoTarjeta() {
    this.mostrarModalPago.set(true);
  }

  onCerrarPagoModal(exito: boolean) {
    this.mostrarModalPago.set(false);
    if (exito) {
      this.mostrarToast('¡Pago con tarjeta procesado y registrado con éxito!');
      const v = this.ticketVenta();
      if (v) {
        this.cargarPagosTicket(v.id);
      }
    }
  }

  abrirPagoQR() {
    this.mostrarModalPagoQR.set(true);
  }

  onCerrarPagoQR(exito: boolean) {
    this.mostrarModalPagoQR.set(false);
    if (exito) {
      this.mostrarToast('¡Pago QR confirmado y registrado con éxito!');
      const v = this.ticketVenta();
      if (v) {
        this.cargarPagosTicket(v.id);
      }
    }
  }

  cerrarTicket() {
    this.ticketVenta.set(null);
    this.pagosTicket.set([]);
  }

  mostrarToast(mensaje: string, esError = false) {
    this.toast.set(mensaje);
    this.toastError.set(esError);
    setTimeout(() => {
      this.toast.set(null);
    }, 4000);
  }
}
