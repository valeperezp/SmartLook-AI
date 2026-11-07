import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { CommonModule, CurrencyPipe, DatePipe } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { forkJoin } from 'rxjs';
import { IconComponent } from '../../../core/components/icon/icon';
import { AccionConflicto, ConflictoSync } from '../../../core/models/conflicto-sync.model';
import { DisponibilidadTallaColor } from '../../../core/models/catalogo.model';
import { CatalogoService } from '../../../core/services/catalogo.service';
import { ConflictosSyncService } from '../../../core/services/conflictos-sync.service';

/** Una prenda del ajuste: la variante original de la venta y las variantes con stock entre las que se puede cambiar. */
export interface FilaAjuste {
  productoId: number;
  nombreProducto: string;
  cantidad: number;
  opciones: DisponibilidadTallaColor[];
  /** Variante elegida: `${talla_id ?? 0}_${color_id ?? 0}`. */
  seleccion: string;
}

export const claveVariante = (tallaId: number | null, colorId: number | null) => `${tallaId ?? 0}_${colorId ?? 0}`;

/**
 * CU13 — Conflictos de sincronización: ventas hechas sin conexión que el servidor no pudo cumplir por falta de stock.
 * El encargado (o el administrador) decide por cada una: anularla, ajustar la variante o forzarla.
 */
@Component({
  selector: 'app-conflictos-sync',
  standalone: true,
  imports: [CommonModule, FormsModule, IconComponent, CurrencyPipe, DatePipe],
  templateUrl: './conflictos-sync.html',
  styleUrl: './conflictos-sync.scss',
})
export class ConflictosSyncPage implements OnInit {
  private service = inject(ConflictosSyncService);
  private catalogo = inject(CatalogoService);

  conflictos = signal<ConflictoSync[]>([]);
  cargando = signal(true);
  error = signal<string | null>(null);
  toast = signal<string | null>(null);

  // Modal de resolución
  seleccionado = signal<ConflictoSync | null>(null);
  modo = signal<'detalle' | 'ajuste'>('detalle');
  /** Acción destructiva a la espera de confirmación (anular / forzar). */
  confirmando = signal<'ANULAR' | 'FORZAR' | null>(null);
  procesando = signal(false);
  errorModal = signal<string | null>(null);
  nota = '';

  // Ajuste de variante
  filasAjuste = signal<FilaAjuste[]>([]);
  cargandoVariantes = signal(false);

  /** El ajuste se puede confirmar si cada prenda tiene variante elegida y una cantidad que alcanza con su stock. */
  ajusteValido = computed(() => {
    const filas = this.filasAjuste();
    return (
      filas.length > 0 &&
      filas.every((f) => {
        const opcion = this.opcionElegida(f);
        return !!opcion && Number.isInteger(f.cantidad) && f.cantidad >= 1 && f.cantidad <= opcion.cantidad_disponible;
      })
    );
  });

  ngOnInit() {
    this.cargar();
  }

  cargar() {
    this.cargando.set(true);
    this.error.set(null);
    this.service.listar().subscribe({
      next: (lista) => {
        this.conflictos.set(lista);
        this.cargando.set(false);
      },
      error: (err) => {
        this.error.set(err.error?.detail || 'No se pudieron cargar los conflictos de sincronización');
        this.cargando.set(false);
      },
    });
  }

  etiquetaVariante(talla: string | null, color: string | null): string {
    return [talla ? `Talla ${talla}` : '', color ?? ''].filter(Boolean).join(' · ') || 'Sin talla ni color';
  }

  // ---------- modal ----------
  abrir(conflicto: ConflictoSync) {
    this.seleccionado.set(conflicto);
    this.modo.set('detalle');
    this.confirmando.set(null);
    this.errorModal.set(null);
    this.nota = '';
  }

  cerrar() {
    if (this.procesando()) return;
    this.seleccionado.set(null);
  }

  pedirConfirmacion(accion: 'ANULAR' | 'FORZAR') {
    this.errorModal.set(null);
    this.confirmando.set(accion);
  }

  cancelarConfirmacion() {
    this.confirmando.set(null);
  }

  /** Anular o forzar: no necesitan más datos que la decisión (y una nota opcional). */
  confirmar(accion: 'ANULAR' | 'FORZAR') {
    this.resolver(accion);
  }

  // ---------- ajustar variante ----------
  iniciarAjuste() {
    const conflicto = this.seleccionado();
    if (!conflicto) return;
    this.errorModal.set(null);
    this.confirmando.set(null);
    this.modo.set('ajuste');
    this.filasAjuste.set([]);
    this.cargandoVariantes.set(true);

    const productos = [...new Set(conflicto.items.map((i) => i.producto_id))];
    forkJoin(productos.map((id) => this.catalogo.obtenerDisponibilidad(id))).subscribe({
      next: (respuestas) => {
        const conStock = new Map<number, DisponibilidadTallaColor[]>();
        respuestas.forEach((r, i) => {
          const suc = r.disponibilidad.find((s) => s.sucursal_id === conflicto.sucursal_id);
          conStock.set(productos[i], (suc?.items ?? []).filter((v) => v.cantidad_disponible > 0));
        });
        this.filasAjuste.set(
          conflicto.items.map((item) => {
            const opciones = conStock.get(item.producto_id) ?? [];
            const original = claveVariante(item.talla_id, item.color_id);
            const inicial = opciones.find((o) => claveVariante(o.talla_id, o.color_id) === original) ?? opciones[0];
            return {
              productoId: item.producto_id,
              nombreProducto: item.nombre_producto,
              cantidad: Math.min(item.cantidad, inicial?.cantidad_disponible ?? 1) || 1,
              opciones,
              seleccion: inicial ? claveVariante(inicial.talla_id, inicial.color_id) : '',
            };
          }),
        );
        this.cargandoVariantes.set(false);
      },
      error: (err) => {
        this.cargandoVariantes.set(false);
        this.errorModal.set(err.error?.detail || 'No se pudo consultar el stock de las variantes');
      },
    });
  }

  volverAlDetalle() {
    this.modo.set('detalle');
    this.errorModal.set(null);
  }

  opcionElegida(fila: FilaAjuste): DisponibilidadTallaColor | undefined {
    return fila.opciones.find((o) => claveVariante(o.talla_id, o.color_id) === fila.seleccion);
  }

  confirmarAjuste() {
    if (!this.ajusteValido()) return;
    const items = this.filasAjuste().map((f) => {
      const o = this.opcionElegida(f)!;
      return { producto_id: f.productoId, talla_id: o.talla_id, color_id: o.color_id, cantidad: f.cantidad };
    });
    this.resolver('AJUSTAR', items);
  }

  private resolver(accion: AccionConflicto, items?: { producto_id: number; talla_id: number | null; color_id: number | null; cantidad: number }[]) {
    const conflicto = this.seleccionado();
    if (!conflicto || this.procesando()) return;
    this.procesando.set(true);
    this.errorModal.set(null);
    this.service.resolver(conflicto.venta_id, accion, items, this.nota.trim() || undefined).subscribe({
      next: () => {
        this.procesando.set(false);
        this.seleccionado.set(null);
        this.mostrarToast(
          accion === 'ANULAR' ? `Venta #${conflicto.venta_id} anulada` : `Venta #${conflicto.venta_id} resuelta (${accion === 'FORZAR' ? 'forzada' : 'ajustada'})`,
        );
        this.cargar();
      },
      error: (err) => {
        this.procesando.set(false);
        this.confirmando.set(null);
        this.errorModal.set(err.error?.detail || 'No se pudo resolver el conflicto');
        if (err.status === 404 || err.status === 409) this.cargar(); // otro encargado ya la resolvió o ya no existe
      },
    });
  }

  private mostrarToast(texto: string) {
    this.toast.set(texto);
    setTimeout(() => {
      if (this.toast() === texto) this.toast.set(null);
    }, 4000);
  }
}
