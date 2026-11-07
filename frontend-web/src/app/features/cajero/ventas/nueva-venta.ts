import { Component, OnInit, computed, effect, inject, signal, untracked } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { CatalogoService } from '../../../core/services/catalogo.service';
import { VentasService } from '../../../core/services/ventas.service';
import { PagosService } from '../../../core/services/pagos.service';
import { AuthService } from '../../../core/services/auth.service';
import { OfflineDbService } from '../../../core/services/offline-db.service';
import { OfflineSyncService } from '../../../core/services/offline-sync.service';
import { Categoria, DisponibilidadTallaColor, Producto } from '../../../core/models/catalogo.model';
import { Venta, VentaPresencialCreate } from '../../../core/models/venta.model';
import { Pago } from '../../../core/models/pago.model';
import { IconComponent } from '../../../core/components/icon/icon';
import { CatalogoDesactualizado } from '../../../core/components/catalogo-desactualizado/catalogo-desactualizado';
import { OfflineBanner } from '../../../core/components/offline-banner/offline-banner';
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
  imports: [CommonModule, FormsModule, IconComponent, PagoModal, PagoQRModal, OfflineBanner, CatalogoDesactualizado],
  templateUrl: './nueva-venta.html',
  styleUrl: './nueva-venta.scss',
})
export class NuevaVenta implements OnInit {
  private catalogoService = inject(CatalogoService);
  private ventasService = inject(VentasService);
  private pagosService = inject(PagosService);
  private offlineDb = inject(OfflineDbService);
  auth = inject(AuthService);
  /** Modo offline: estado de la red y operaciones pendientes (IndexedDB). */
  offline = inject(OfflineSyncService);

  /** CU13: si el catálogo guardado cambia (una venta offline descontó stock o un rechazo lo devolvió) y es el que se muestra, se relee. */
  private readonly alCambiarCatalogoLocal = effect(() => {
    this.offline.catalogoVersion();
    untracked(() => {
      if (this.catalogoLocal()) void this.cargarDesdeCatalogoLocal();
    });
  });

  user = this.auth.currentUser;

  private readonly mensajeSinSucursal =
    'Tu usuario no tiene una sucursal asignada. P\u00eddele a un administrador que te asigne una.';

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
  /** Los productos en pantalla vienen del catálogo guardado en el dispositivo (no hubo servidor). */
  catalogoLocal = signal<boolean>(false);

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
      error: () => {
        if (navigator.onLine !== false) this.mostrarToast('Error al cargar categorías', true); // sin red lo dice el banner
      },
    });
  }

  cargarProductos() {
    this.cargandoProductos.set(true);
    const sucursalId = this.user()?.sucursal_id || undefined;
    this.catalogoService.listarProductos(false, sucursalId).subscribe({
      next: (prods) => {
        this.productos.set(prods);
        this.catalogoLocal.set(false);
        this.cargandoProductos.set(false);
      },
      error: () => {
        this.cargandoProductos.set(false);
        void this.cargarDesdeCatalogoLocal().then((hayCatalogo) => {
          if (hayCatalogo) return;
          this.mostrarToast(
            navigator.onLine === false
              ? 'Sin conexión y sin catálogo guardado: descárgalo con conexión desde el catálogo ("Descargar catálogo para Offline").'
              : 'Error al cargar catálogo de productos',
            true,
          );
        });
      },
    });
  }

  /** Sin servidor: productos y categorías del catálogo descargado para offline, solo de la sucursal del cajero. */
  private async cargarDesdeCatalogoLocal(): Promise<boolean> {
    try {
      const sucursalId = this.user()?.sucursal_id;
      const filas = (await this.offlineDb.obtenerCatalogo(this.offline.empresaActual())).filter((f) => !sucursalId || f.sucursal_id === sucursalId);
      if (filas.length === 0) return false;
      const productos = new Map<number, Producto>();
      const categorias = new Map<number, Categoria>();
      for (const f of filas) {
        if (productos.has(f.producto_id)) continue;
        const categoria: Categoria = { id: f.categoria_id ?? 0, nombre: f.nombre_categoria ?? 'Sin categoría', activo: true };
        productos.set(f.producto_id, {
          id: f.producto_id,
          nombre: f.nombre_producto,
          descripcion: f.descripcion ?? undefined,
          precio: f.precio_centavos / 100,
          categoria_id: categoria.id,
          imagen_url: f.imagen_url ?? undefined,
          activo: true,
          categoria,
        });
        if (f.categoria_id !== null) categorias.set(categoria.id, categoria);
      }
      this.productos.set([...productos.values()]);
      this.categorias.set([...categorias.values()]);
      this.catalogoLocal.set(true);
      return true;
    } catch (error) {
      console.error('[TPV] No se pudo leer el catálogo guardado', error);
      return false;
    }
  }

  /** Tallas y colores con stock de un producto, según el catálogo guardado (para vender sin conexión). */
  private async variantesLocalesDe(productoId: number, sucursalId: number): Promise<DisponibilidadTallaColor[]> {
    const filas = await this.offlineDb.obtenerCatalogo(this.offline.empresaActual());
    return filas
      .filter((f) => f.producto_id === productoId && f.sucursal_id === sucursalId)
      .map((f) => ({
        talla_id: f.talla_id,
        nombre_talla: f.nombre_talla,
        color_id: f.color_id,
        nombre_color: f.nombre_color,
        cantidad_disponible: f.cantidad_disponible,
        cantidad_reservada: 0,
        cantidad_vendida: 0,
      }));
  }

  private aplicarVariantes(items: DisponibilidadTallaColor[]) {
    const conStock = items.filter((i) => i.cantidad_disponible > 0);
    this.variantesDisponibles.set(conStock);
    if (conStock.length > 0) this.varianteSeleccionada.set(conStock[0]);
  }

  abrirSelectorVariante(prod: Producto) {
    const sucursalId = this.user()?.sucursal_id;
    if (!sucursalId) {
      this.mostrarToast(this.mensajeSinSucursal, true);
      return;
    }
    this.productoParaAgregar.set(prod);
    this.cantidadParaAgregar.set(1);
    this.varianteSeleccionada.set(null);
    this.variantesDisponibles.set([]);
    this.cargandoVariantes.set(true);
    this.modalVarianteAbierto.set(true);

    if (navigator.onLine === false) {
      // Sin red no hay a quién preguntarle el stock: se usa el del catálogo guardado en el dispositivo
      void this.variantesLocalesDe(prod.id, sucursalId).then((items) => {
        this.cargandoVariantes.set(false);
        this.aplicarVariantes(items);
      });
      return;
    }

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

    const sucursalId = this.user()?.sucursal_id;
    if (!sucursalId) {
      this.mostrarToast(this.mensajeSinSucursal, true);
      return;
    }

    if (navigator.onLine === false) {
      void this.cobrarSinConexion(sucursalId);
      return;
    }

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

  /**
   * Sin conexión: la venta se guarda en IndexedDB (con su uuid) y se enviará sola a `POST /sync/operaciones` al volver la
   * red. No hay ticket ni pagos todavía: eso existe cuando el servidor la recibe. El carrito se limpia solo si se guardó.
   */
  private async cobrarSinConexion(sucursalId: number) {
    this.procesando.set(true);
    try {
      await this.offline.registrarOperacion({
        tipo_operacion: 'VENTA_CONTADO',
        sucursal_id: sucursalId,
        cajero_id: this.user()?.id ?? null,
        cliente_id: this.clienteId() ? Number(this.clienteId()) : null,
        items: this.carrito().map((item) => ({
          producto_id: item.productoId,
          talla_id: item.tallaId,
          color_id: item.colorId,
          nombre_producto: item.nombreProducto,
          cantidad: item.cantidad,
          precio_unitario_centavos: Math.round(item.precio * 100),
        })),
      });
      this.vaciarCarrito();
      this.clienteId.set(null);
      this.mostrarToast('Venta guardada localmente. Se sincronizará cuando vuelva la conexión');
    } catch (error) {
      // No se pudo guardar: el carrito se conserva para no perder la venta
      this.mostrarToast(error instanceof Error ? error.message : 'No se pudo guardar la venta en este dispositivo', true);
    } finally {
      this.procesando.set(false);
    }
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
