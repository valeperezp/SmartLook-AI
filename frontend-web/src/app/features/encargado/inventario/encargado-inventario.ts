import { Component, OnInit, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { IconComponent } from '../../../core/components/icon/icon';
import { InventarioService } from '../../../core/services/inventario.service';
import { InventarioItem } from '../../../core/models/inventario.model';

type ModalAccion = 'entrada' | 'salida' | 'ajuste' | 'stock_minimo' | null;

@Component({
  selector: 'app-encargado-inventario',
  standalone: true,
  imports: [CommonModule, FormsModule, IconComponent],
  template: `
    <div class="page-header">
      <div>
        <h1>Inventario de Sucursal</h1>
        <p>Control de existencias y registro de movimientos de mercancía.</p>
      </div>
      <div class="header-actions">
        <button class="btn-secondary" (click)="cargar()" [disabled]="cargando()">
          <app-icon name="sparkles" [size]="16" />
          <span>Actualizar</span>
        </button>
      </div>
    </div>

    @if (toast()) {
      <div class="toast-notification" [class.toast-error]="toastIsError()">
        {{ toast() }}
      </div>
    }

    <!-- Filtros y Búsqueda -->
    <div class="card filters-card" style="margin-bottom: 1.5rem;">
      <div class="search-box">
        <app-icon name="search" [size]="18" />
        <input
          type="text"
          placeholder="Buscar producto por nombre..."
          [(ngModel)]="terminoBusqueda"
          (ngModelChange)="filtrar()"
        />
      </div>

      <div class="filter-pills">
        <button
          type="button"
          class="pill-btn"
          [class.active]="filtroEstado === 'todos'"
          (click)="setFiltroEstado('todos')"
        >
          Todos ({{ totalItems() }})
        </button>
        <button
          type="button"
          class="pill-btn"
          [class.active]="filtroEstado === 'disponibles'"
          (click)="setFiltroEstado('disponibles')"
        >
          Disponibles
        </button>
        <button
          type="button"
          class="pill-btn"
          [class.active]="filtroEstado === 'bajo'"
          (click)="setFiltroEstado('bajo')"
        >
          Stock Bajo ({{ totalBajo() }})
        </button>
        <button
          type="button"
          class="pill-btn"
          [class.active]="filtroEstado === 'agotados'"
          (click)="setFiltroEstado('agotados')"
        >
          Agotados ({{ totalAgotados() }})
        </button>
      </div>
    </div>

    <!-- Tabla de Existencias -->
    <div class="card table-card">
      <table class="data-table">
        <thead>
          <tr>
            <th>Producto</th>
            <th>Talla</th>
            <th>Color</th>
            <th class="text-right">Disponible</th>
            <th class="text-right">Reservado</th>
            <th class="text-right">Vendido</th>
            <th class="text-right">Mínimo</th>
            <th>Estado</th>
            <th class="text-center">Operaciones</th>
          </tr>
        </thead>
        <tbody>
          @if (cargando()) {
            <tr>
              <td colspan="9" class="text-center py-4">Cargando existencias de la sucursal...</td>
            </tr>
          } @else if (inventarioFiltrado().length === 0) {
            <tr>
              <td colspan="9" class="text-center py-4">No se encontraron artículos con los filtros aplicados.</td>
            </tr>
          } @else {
            @for (item of inventarioFiltrado(); track item.id) {
              <tr [class.row-alert]="item.estado !== 'disponible'">
                <td>
                  <strong>{{ item.nombre_producto }}</strong>
                </td>
                <td>{{ item.nombre_talla || '—' }}</td>
                <td>{{ item.nombre_color || '—' }}</td>
                <td class="text-right font-bold">{{ item.cantidad_disponible }}</td>
                <td class="text-right text-muted">{{ item.cantidad_reservada }}</td>
                <td class="text-right text-muted">{{ item.cantidad_vendida }}</td>
                <td class="text-right">{{ item.stock_minimo }}</td>
                <td>
                  <span
                    class="badge"
                    [class.badge-success]="item.estado === 'disponible'"
                    [class.badge-warning]="item.estado === 'bajo'"
                    [class.badge-danger]="item.estado === 'agotado'"
                  >
                    {{ item.estado | uppercase }}
                  </span>
                </td>
                <td class="actions-cell">
                  <div class="btn-group">
                    <button
                      type="button"
                      class="btn-action btn-in"
                      title="Entrada de mercancía"
                      (click)="abrirModal('entrada', item)"
                    >
                      + Entrada
                    </button>
                    <button
                      type="button"
                      class="btn-action btn-out"
                      title="Salida o merma"
                      [disabled]="item.cantidad_disponible <= 0"
                      (click)="abrirModal('salida', item)"
                    >
                      - Salida
                    </button>
                    <button
                      type="button"
                      class="btn-action btn-adj"
                      title="Ajuste físico"
                      (click)="abrirModal('ajuste', item)"
                    >
                      Ajuste
                    </button>
                    <button
                      type="button"
                      class="btn-action btn-opt"
                      title="Editar stock mínimo"
                      (click)="abrirModal('stock_minimo', item)"
                    >
                      Mínimo
                    </button>
                  </div>
                </td>
              </tr>
            }
          }
        </tbody>
      </table>
    </div>

    <!-- Modal de Acción Operativa -->
    @if (modalActivo()) {
      <div class="modal-overlay" (click)="cerrarModal()">
        <div class="modal-card" (click)="$event.stopPropagation()">
          <div class="modal-header">
            <h3>{{ modalTitulo() }}</h3>
            <button type="button" class="btn-close" (click)="cerrarModal()">&times;</button>
          </div>

          <div class="modal-body">
            @if (itemSeleccionado()) {
              <div class="item-context">
                <strong>{{ itemSeleccionado()?.nombre_producto }}</strong>
                <p>
                  Talla: {{ itemSeleccionado()?.nombre_talla || 'Única' }} | Color: {{ itemSeleccionado()?.nombre_color || 'N/A' }} |
                  Stock actual: <b>{{ itemSeleccionado()?.cantidad_disponible }} un.</b>
                </p>
              </div>
            }

            @if (modalActivo() === 'entrada' || modalActivo() === 'salida') {
              <div class="form-group">
                <label>Cantidad de unidades</label>
                <input
                  type="number"
                  min="1"
                  [max]="modalActivo() === 'salida' ? (itemSeleccionado()?.cantidad_disponible || 1) : 9999"
                  [(ngModel)]="formulario.cantidad"
                  placeholder="Ej: 5"
                />
              </div>
              <div class="form-group">
                <label>Motivo o referencia</label>
                <input
                  type="text"
                  [(ngModel)]="formulario.motivo"
                  [placeholder]="modalActivo() === 'entrada' ? 'Ej: Factura Proveedor / Remisión' : 'Ej: Merma / Daño / Devolución'"
                />
              </div>
            }

            @if (modalActivo() === 'ajuste') {
              <div class="form-group">
                <label>Nueva cantidad física disponible (conteo real)</label>
                <input
                  type="number"
                  min="0"
                  [(ngModel)]="formulario.nueva_cantidad"
                  placeholder="Ej: 12"
                />
              </div>
              <div class="form-group">
                <label>Motivo del ajuste</label>
                <input
                  type="text"
                  [(ngModel)]="formulario.motivo"
                  placeholder="Ej: Conteo físico mensual / Corrección de descuadre"
                />
              </div>
            }

            @if (modalActivo() === 'stock_minimo') {
              <div class="form-group">
                <label>Nuevo umbral de stock mínimo</label>
                <input
                  type="number"
                  min="0"
                  [(ngModel)]="formulario.stock_minimo"
                  placeholder="Ej: 5"
                />
                <small class="form-hint">Cuando las existencias sean menores o iguales a este número se generará una alerta.</small>
              </div>
            }
          </div>

          <div class="modal-footer">
            <button type="button" class="btn-secondary" (click)="cerrarModal()" [disabled]="guardando()">
              Cancelar
            </button>
            <button type="button" class="btn-primary" (click)="ejecutarAccion()" [disabled]="guardando()">
              @if (guardando()) { Procesando... } @else { Confirmar acción }
            </button>
          </div>
        </div>
      </div>
    }
  `,
  styleUrl: './encargado-inventario.scss',
})
export class EncargadoInventario implements OnInit {
  private inventarioService = inject(InventarioService);

  inventario = signal<InventarioItem[]>([]);
  inventarioFiltrado = signal<InventarioItem[]>([]);
  cargando = signal<boolean>(false);
  guardando = signal<boolean>(false);

  toast = signal<string | null>(null);
  toastIsError = signal<boolean>(false);

  terminoBusqueda = '';
  filtroEstado: 'todos' | 'disponibles' | 'bajo' | 'agotados' = 'todos';

  modalActivo = signal<ModalAccion>(null);
  itemSeleccionado = signal<InventarioItem | null>(null);

  formulario = {
    cantidad: 1,
    nueva_cantidad: 0,
    stock_minimo: 5,
    motivo: '',
  };

  ngOnInit() {
    this.cargar();
  }

  cargar() {
    this.cargando.set(true);
    this.inventarioService.miSucursal().subscribe({
      next: (data) => {
        this.inventario.set(data);
        this.filtrar();
        this.cargando.set(false);
      },
      error: (err) => {
        console.error('Error al cargar inventario de mi sucursal', err);
        this.mostrarToast('Error al obtener inventario de la sucursal', true);
        this.cargando.set(false);
      },
    });
  }

  totalItems(): number {
    return this.inventario().length;
  }

  totalBajo(): number {
    return this.inventario().filter((i) => i.estado === 'bajo').length;
  }

  totalAgotados(): number {
    return this.inventario().filter((i) => i.estado === 'agotado').length;
  }

  setFiltroEstado(estado: 'todos' | 'disponibles' | 'bajo' | 'agotados') {
    this.filtroEstado = estado;
    this.filtrar();
  }

  filtrar() {
    let items = this.inventario();

    if (this.terminoBusqueda.trim()) {
      const q = this.terminoBusqueda.toLowerCase();
      items = items.filter(
        (i) =>
          i.nombre_producto.toLowerCase().includes(q) ||
          (i.nombre_talla && i.nombre_talla.toLowerCase().includes(q)) ||
          (i.nombre_color && i.nombre_color.toLowerCase().includes(q))
      );
    }

    if (this.filtroEstado === 'disponibles') {
      items = items.filter((i) => i.cantidad_disponible > 0);
    } else if (this.filtroEstado === 'bajo') {
      items = items.filter((i) => i.estado === 'bajo');
    } else if (this.filtroEstado === 'agotados') {
      items = items.filter((i) => i.estado === 'agotado');
    }

    this.inventarioFiltrado.set(items);
  }

  abrirModal(accion: ModalAccion, item: InventarioItem) {
    this.modalActivo.set(accion);
    this.itemSeleccionado.set(item);
    this.formulario = {
      cantidad: 1,
      nueva_cantidad: item.cantidad_disponible,
      stock_minimo: item.stock_minimo,
      motivo: '',
    };
  }

  cerrarModal() {
    this.modalActivo.set(null);
    this.itemSeleccionado.set(null);
  }

  modalTitulo(): string {
    switch (this.modalActivo()) {
      case 'entrada':
        return 'Registrar Entrada de Mercancía';
      case 'salida':
        return 'Registrar Salida / Merma';
      case 'ajuste':
        return 'Ajuste de Stock por Conteo Físico';
      case 'stock_minimo':
        return 'Modificar Nivel de Stock Mínimo';
      default:
        return 'Operación de Inventario';
    }
  }

  ejecutarAccion() {
    const item = this.itemSeleccionado();
    if (!item) return;

    this.guardando.set(true);
    const accion = this.modalActivo();

    if (accion === 'entrada' || accion === 'salida') {
      if (!this.formulario.cantidad || this.formulario.cantidad <= 0) {
        this.mostrarToast('La cantidad debe ser mayor a 0', true);
        this.guardando.set(false);
        return;
      }
      if (accion === 'salida' && this.formulario.cantidad > item.cantidad_disponible) {
        this.mostrarToast(`Stock insuficiente. Solo hay ${item.cantidad_disponible} disponibles.`, true);
        this.guardando.set(false);
        return;
      }

      this.inventarioService
        .crearMovimiento({
          inventario_id: item.id,
          tipo: accion,
          cantidad: this.formulario.cantidad,
          motivo: this.formulario.motivo || (accion === 'entrada' ? 'Entrada de mercancía' : 'Salida de mercancía'),
        })
        .subscribe({
          next: () => {
            this.mostrarToast(`Movimiento de ${accion} registrado con éxito`);
            this.guardando.set(false);
            this.cerrarModal();
            this.cargar();
          },
          error: (err) => {
            this.mostrarToast(err.error?.detail || `Error al registrar ${accion}`, true);
            this.guardando.set(false);
          },
        });
    } else if (accion === 'ajuste') {
      if (this.formulario.nueva_cantidad < 0) {
        this.mostrarToast('La cantidad física no puede ser negativa', true);
        this.guardando.set(false);
        return;
      }

      this.inventarioService
        .ajustarStock({
          inventario_id: item.id,
          nueva_cantidad: this.formulario.nueva_cantidad,
          motivo: this.formulario.motivo || 'Ajuste por conteo físico',
        })
        .subscribe({
          next: () => {
            this.mostrarToast('Stock físico ajustado correctamente');
            this.guardando.set(false);
            this.cerrarModal();
            this.cargar();
          },
          error: (err) => {
            this.mostrarToast(err.error?.detail || 'Error al ajustar stock', true);
            this.guardando.set(false);
          },
        });
    } else if (accion === 'stock_minimo') {
      if (this.formulario.stock_minimo < 0) {
        this.mostrarToast('El stock mínimo no puede ser negativo', true);
        this.guardando.set(false);
        return;
      }

      this.inventarioService
        .actualizarStockMinimo(item.id, this.formulario.stock_minimo)
        .subscribe({
          next: () => {
            this.mostrarToast('Nivel de stock mínimo actualizado');
            this.guardando.set(false);
            this.cerrarModal();
            this.cargar();
          },
          error: (err) => {
            this.mostrarToast(err.error?.detail || 'Error al actualizar stock mínimo', true);
            this.guardando.set(false);
          },
        });
    }
  }

  private mostrarToast(mensaje: string, esError = false) {
    this.toast.set(mensaje);
    this.toastIsError.set(esError);
    setTimeout(() => this.toast.set(null), 3500);
  }
}
