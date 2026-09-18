import { Injectable, signal, computed, effect } from '@angular/core';
import { ItemCarrito } from '../models/carrito.model';

const STORAGE_KEY = 'smartlook_cart';

@Injectable({ providedIn: 'root' })
export class CarritoService {
  items = signal<ItemCarrito[]>([]);

  total = computed(() =>
    this.items().reduce((acc, item) => acc + item.precio * item.cantidad, 0)
  );

  cantidadTotal = computed(() =>
    this.items().reduce((acc, item) => acc + item.cantidad, 0)
  );

  estaVacio = computed(() => this.items().length === 0);

  constructor() {
    this.cargarDeStorage();

    // Sincronizar automáticamente cualquier cambio en el signal con localStorage
    effect(() => {
      const current = this.items();
      try {
        localStorage.setItem(STORAGE_KEY, JSON.stringify(current));
      } catch (err) {
        console.error('Error al guardar el carrito en localStorage:', err);
      }
    });
  }

  private cargarDeStorage() {
    try {
      const raw = localStorage.getItem(STORAGE_KEY);
      if (raw) {
        const parsed = JSON.parse(raw);
        if (Array.isArray(parsed)) {
          this.items.set(parsed);
        }
      }
    } catch (err) {
      console.error('Error al leer el carrito de localStorage:', err);
      this.items.set([]);
    }
  }

  agregar(nuevo: ItemCarrito) {
    if (nuevo.cantidad <= 0) return;

    this.items.update((actuales) => {
      const index = actuales.findIndex(
        (it) =>
          it.productoId === nuevo.productoId &&
          it.tallaId === nuevo.tallaId &&
          it.colorId === nuevo.colorId
      );

      if (index > -1) {
        const itemExistente = actuales[index];
        let nuevaCantidad = itemExistente.cantidad + nuevo.cantidad;
        if (itemExistente.maxDisponible && nuevaCantidad > itemExistente.maxDisponible) {
          nuevaCantidad = itemExistente.maxDisponible;
        }

        const actualizados = [...actuales];
        actualizados[index] = {
          ...itemExistente,
          cantidad: nuevaCantidad,
        };
        return actualizados;
      } else {
        let cantidadFinal = nuevo.cantidad;
        if (nuevo.maxDisponible && cantidadFinal > nuevo.maxDisponible) {
          cantidadFinal = nuevo.maxDisponible;
        }
        return [...actuales, { ...nuevo, cantidad: cantidadFinal }];
      }
    });
  }

  actualizarCantidad(index: number, cantidad: number) {
    if (cantidad <= 0) {
      this.eliminar(index);
      return;
    }

    this.items.update((actuales) => {
      if (index < 0 || index >= actuales.length) return actuales;

      const item = actuales[index];
      let cantFinal = cantidad;
      if (item.maxDisponible && cantFinal > item.maxDisponible) {
        cantFinal = item.maxDisponible;
      }

      const actualizados = [...actuales];
      actualizados[index] = {
        ...item,
        cantidad: cantFinal,
      };
      return actualizados;
    });
  }

  eliminar(index: number) {
    this.items.update((actuales) => actuales.filter((_, i) => i !== index));
  }

  vaciar() {
    this.items.set([]);
  }
}
