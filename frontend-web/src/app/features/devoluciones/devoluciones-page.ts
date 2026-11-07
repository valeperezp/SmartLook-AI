import { Component, computed, inject, signal } from '@angular/core';
import { CommonModule, CurrencyPipe, DatePipe } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { IconComponent } from '../../core/components/icon/icon';
import { DisponibilidadTallaColor, Producto } from '../../core/models/catalogo.model';
import {
  DevolucionCreate,
  DevolucionOut,
  ItemDevolucionIn,
  ItemVentaDevolvible,
  TipoDevolucion,
  VentaDevolvible,
} from '../../core/models/devolucion.model';
import { CatalogoService } from '../../core/services/catalogo.service';
import { DevolucionesService } from '../../core/services/devoluciones.service';

/** Una prenda nueva que el cliente se lleva en un cambio. */
export interface PrendaNueva {
  producto_id: number;
  nombre: string;
  talla_id: number | null;
  nombre_talla: string | null;
  color_id: number | null;
  nombre_color: string | null;
  cantidad: number;
  precio: number;
}

export const claveItem = (i: { producto_id: number; talla_id: number | null; color_id: number | null }) =>
  `${i.producto_id}_${i.talla_id ?? 0}_${i.color_id ?? 0}`;

/**
 * CU11 — Cambios y devoluciones desde la web (cajero, encargado y administrador).
 * Se busca la venta por ticket o UUID, se elige qué devolver y, si es un cambio, qué se lleva el cliente en su lugar.
 * El plazo de días, las cantidades y el stock los valida el backend: aquí solo se muestran su aviso o su rechazo.
 */
@Component({
  selector: 'app-devoluciones-page',
  standalone: true,
  imports: [CommonModule, FormsModule, IconComponent, CurrencyPipe, DatePipe],
  templateUrl: './devoluciones-page.html',
  styleUrl: './devoluciones-page.scss',
})
export class DevolucionesPage {
  private service = inject(DevolucionesService);
  private catalogo = inject(CatalogoService);

  // ---------- búsqueda ----------
  busqueda = '';
  buscando = signal(false);
  errorBusqueda = signal<string | null>(null);
  venta = signal<VentaDevolvible | null>(null);

  // ---------- qué se devuelve ----------
  /** Unidades a devolver por prenda (clave producto_talla_color). */
  aDevolver = signal<Record<string, number>>({});
  tipo = signal<TipoDevolucion>('devolucion');
  motivo = '';

  // ---------- cambio: qué se lleva ----------
  productos = signal<Producto[]>([]);
  cargandoProductos = signal(false);
  productoNuevoId = signal<number | null>(null);
  variantes = signal<DisponibilidadTallaColor[]>([]);
  cargandoVariantes = signal(false);
  varianteNueva = '';
  cantidadNueva = 1;
  nuevas = signal<PrendaNueva[]>([]);

  // ---------- resultado ----------
  procesando = signal(false);
  resultado = signal<DevolucionOut | null>(null);
  errorProceso = signal<string | null>(null);

  itemsADevolver = computed<ItemDevolucionIn[]>(() => {
    const v = this.venta();
    if (!v) return [];
    const cantidades = this.aDevolver();
    return v.items
      .filter((i) => (cantidades[claveItem(i)] ?? 0) > 0)
      .map((i) => ({ producto_id: i.producto_id, talla_id: i.talla_id, color_id: i.color_id, cantidad: cantidades[claveItem(i)] }));
  });

  /** Lo que se reembolsa: precio de la venta original × unidades devueltas. */
  totalDevuelto = computed(() => {
    const v = this.venta();
    const cantidades = this.aDevolver();
    return v ? v.items.reduce((suma, i) => suma + i.precio_unitario * (cantidades[claveItem(i)] ?? 0), 0) : 0;
  });
  totalNuevo = computed(() => this.nuevas().reduce((suma, n) => suma + n.precio * n.cantidad, 0));
  /** nuevo - devuelto: positivo = el cliente paga la diferencia; negativo = se le devuelve. */
  diferencia = computed(() => Math.round((this.totalNuevo() - this.totalDevuelto()) * 100) / 100);

  puedeProcesar = computed(
    () =>
      !this.procesando() &&
      this.itemsADevolver().length > 0 &&
      (this.tipo() === 'devolucion' || this.nuevas().length > 0),
  );

  etiquetaVariante(talla: string | null, color: string | null): string {
    return [talla ? `Talla ${talla}` : '', color ?? ''].filter(Boolean).join(' · ') || 'Sin talla ni color';
  }

  // ---------- búsqueda de la venta ----------
  buscar() {
    const texto = this.busqueda.trim();
    if (!texto || this.buscando()) return;
    this.buscando.set(true);
    this.errorBusqueda.set(null);
    this.limpiarSeleccion();
    this.resultado.set(null);
    this.service.buscar(texto).subscribe({
      next: (venta) => {
        this.venta.set(venta);
        this.buscando.set(false);
      },
      error: (err) => {
        this.venta.set(null);
        this.buscando.set(false);
        this.errorBusqueda.set(err.error?.detail || 'No se pudo buscar la venta');
      },
    });
  }

  nuevaBusqueda() {
    this.venta.set(null);
    this.busqueda = '';
    this.resultado.set(null);
    this.errorProceso.set(null);
    this.limpiarSeleccion();
  }

  private limpiarSeleccion() {
    this.aDevolver.set({});
    this.tipo.set('devolucion');
    this.motivo = '';
    this.nuevas.set([]);
    this.productoNuevoId.set(null);
    this.variantes.set([]);
    this.varianteNueva = '';
    this.cantidadNueva = 1;
    this.errorProceso.set(null);
  }

  // ---------- cantidades a devolver ----------
  cantidadDe(item: ItemVentaDevolvible): number {
    return this.aDevolver()[claveItem(item)] ?? 0;
  }

  /** Fija las unidades a devolver de una prenda, sin pasarse de las que se pueden devolver. */
  fijarCantidad(item: ItemVentaDevolvible, valor: number | string | null) {
    const n = Math.floor(Number(valor));
    const limpia = Number.isFinite(n) ? Math.min(Math.max(n, 0), item.cantidad_devolvible) : 0;
    this.aDevolver.update((actual) => ({ ...actual, [claveItem(item)]: limpia }));
  }

  devolverTodo(item: ItemVentaDevolvible) {
    this.fijarCantidad(item, item.cantidad_devolvible);
  }

  // ---------- tipo de operación ----------
  elegirTipo(tipo: TipoDevolucion) {
    this.tipo.set(tipo);
    this.errorProceso.set(null);
    if (tipo === 'cambio' && this.productos().length === 0 && !this.cargandoProductos()) this.cargarProductos();
  }

  private cargarProductos() {
    const v = this.venta();
    if (!v) return;
    this.cargandoProductos.set(true);
    this.catalogo.listarProductos(false, v.sucursal_id).subscribe({
      next: (lista) => {
        this.productos.set(lista.filter((p) => p.activo !== false));
        this.cargandoProductos.set(false);
      },
      error: () => {
        this.cargandoProductos.set(false);
        this.errorProceso.set('No se pudo cargar el catálogo para el cambio');
      },
    });
  }

  elegirProductoNuevo(id: number | string | null) {
    const productoId = id === null || id === '' ? null : Number(id);
    this.productoNuevoId.set(productoId);
    this.variantes.set([]);
    this.varianteNueva = '';
    this.cantidadNueva = 1;
    const v = this.venta();
    if (productoId === null || !v) return;
    this.cargandoVariantes.set(true);
    this.catalogo.obtenerDisponibilidad(productoId).subscribe({
      next: (disp) => {
        const suc = disp.disponibilidad.find((s) => s.sucursal_id === v.sucursal_id);
        const conStock = (suc?.items ?? []).filter((i) => i.cantidad_disponible > 0);
        this.variantes.set(conStock);
        this.varianteNueva = conStock.length ? `${conStock[0].talla_id}_${conStock[0].color_id}` : '';
        this.cargandoVariantes.set(false);
      },
      error: () => {
        this.cargandoVariantes.set(false);
        this.errorProceso.set('No se pudo consultar el stock del producto');
      },
    });
  }

  private varianteElegida(): DisponibilidadTallaColor | undefined {
    return this.variantes().find((i) => `${i.talla_id}_${i.color_id}` === this.varianteNueva);
  }

  puedeAgregarNueva(): boolean {
    const variante = this.varianteElegida();
    return !!variante && Number.isInteger(this.cantidadNueva) && this.cantidadNueva >= 1 && this.cantidadNueva <= variante.cantidad_disponible;
  }

  agregarNueva() {
    const producto = this.productos().find((p) => p.id === this.productoNuevoId());
    const variante = this.varianteElegida();
    if (!producto || !variante || !this.puedeAgregarNueva()) return;
    const nueva: PrendaNueva = {
      producto_id: producto.id,
      nombre: producto.nombre,
      talla_id: variante.talla_id,
      nombre_talla: variante.nombre_talla,
      color_id: variante.color_id,
      nombre_color: variante.nombre_color,
      cantidad: this.cantidadNueva,
      precio: Number(producto.precio),
    };
    this.nuevas.update((lista) => {
      const clave = claveItem(nueva);
      const existente = lista.find((n) => claveItem(n) === clave);
      return existente ? lista.map((n) => (n === existente ? { ...n, cantidad: n.cantidad + nueva.cantidad } : n)) : [...lista, nueva];
    });
    this.cantidadNueva = 1;
  }

  quitarNueva(nueva: PrendaNueva) {
    this.nuevas.update((lista) => lista.filter((n) => n !== nueva));
  }

  // ---------- procesar ----------
  procesar() {
    const v = this.venta();
    if (!v || !this.puedeProcesar()) return;
    const cuerpo: DevolucionCreate = {
      venta_id: v.venta_id,
      tipo: this.tipo(),
      items_devueltos: this.itemsADevolver(),
      items_nuevos:
        this.tipo() === 'cambio'
          ? this.nuevas().map((n) => ({ producto_id: n.producto_id, talla_id: n.talla_id, color_id: n.color_id, cantidad: n.cantidad }))
          : [],
      ...(this.motivo.trim() ? { motivo: this.motivo.trim() } : {}),
    };
    this.procesando.set(true);
    this.errorProceso.set(null);
    this.service.registrar(cuerpo).subscribe({
      next: (res) => {
        this.procesando.set(false);
        this.resultado.set(res);
        // Se vuelve a pedir la venta: ya no se pueden devolver las unidades que acaban de salir
        this.service.buscar(String(v.venta_id)).subscribe({
          next: (actualizada) => this.venta.set(actualizada),
        });
        this.limpiarSeleccion();
      },
      error: (err) => {
        this.procesando.set(false);
        // plazo vencido, cantidades o stock: el motivo lo dice el servidor
        this.errorProceso.set(err.error?.detail || 'No se pudo registrar la devolución');
      },
    });
  }
}
