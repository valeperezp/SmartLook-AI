import { Component, OnInit, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { IconComponent } from '../../../core/components/icon/icon';
import { InventarioService } from '../../../core/services/inventario.service';
import { MovimientoInventario } from '../../../core/models/inventario.model';

@Component({
  selector: 'app-encargado-movimientos',
  standalone: true,
  imports: [CommonModule, FormsModule, IconComponent],
  template: `
    <div class="page-header">
      <div>
        <h1>Historial de Movimientos</h1>
        <p>Auditoría de entradas, salidas y ajustes de inventario en tu sucursal.</p>
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

    <!-- Filtros de Movimientos -->
    <div class="card filters-card" style="margin-bottom: 1.5rem;">
      <div class="filter-controls">
        <div class="filter-pills">
          <button
            type="button"
            class="pill-btn"
            [class.active]="filtroTipo === 'todos'"
            (click)="setFiltroTipo('todos')"
          >
            Todos los movimientos
          </button>
          <button
            type="button"
            class="pill-btn"
            [class.active]="filtroTipo === 'entrada'"
            (click)="setFiltroTipo('entrada')"
          >
            Entradas
          </button>
          <button
            type="button"
            class="pill-btn"
            [class.active]="filtroTipo === 'salida'"
            (click)="setFiltroTipo('salida')"
          >
            Salidas / Mermas
          </button>
          <button
            type="button"
            class="pill-btn"
            [class.active]="filtroTipo === 'ajuste'"
            (click)="setFiltroTipo('ajuste')"
          >
            Ajustes de conteo
          </button>
        </div>

        <div class="search-box">
          <app-icon name="search" [size]="16" />
          <input
            type="text"
            placeholder="Buscar por producto, motivo o responsable..."
            [(ngModel)]="terminoBusqueda"
            (ngModelChange)="filtrar()"
          />
        </div>
      </div>
    </div>

    <!-- Tabla de Movimientos -->
    <div class="card table-card">
      <table class="data-table">
        <thead>
          <tr>
            <th>Fecha y Hora</th>
            <th>Producto</th>
            <th>Tipo</th>
            <th class="text-right">Cantidad</th>
            <th>Motivo / Referencia</th>
            <th>Responsable</th>
          </tr>
        </thead>
        <tbody>
          @if (cargando()) {
            <tr>
              <td colspan="6" class="text-center py-4">Cargando historial de movimientos...</td>
            </tr>
          } @else if (movimientosFiltrados().length === 0) {
            <tr>
              <td colspan="6" class="text-center py-4">No se encontraron movimientos registrados con los filtros aplicados.</td>
            </tr>
          } @else {
            @for (m of movimientosFiltrados(); track m.id) {
              <tr>
                <td class="date-cell">
                  {{ m.creado_en | date: 'dd/MM/yyyy HH:mm' }}
                </td>
                <td>
                  <strong>{{ m.nombre_producto || 'ID Inv #' + m.inventario_id }}</strong>
                </td>
                <td>
                  <span class="badge" [ngClass]="badgeClass(m.tipo)">
                    {{ m.tipo | uppercase }}
                  </span>
                </td>
                <td class="text-right font-bold" [ngClass]="cantidadClass(m.tipo)">
                  {{ formatoCantidad(m) }}
                </td>
                <td>
                  <span class="motivo-text">{{ m.motivo || '—' }}</span>
                </td>
                <td>
                  <span class="usuario-pill">
                    <app-icon name="user" [size]="14" />
                    <span>{{ m.nombre_usuario || 'Sistema' }}</span>
                  </span>
                </td>
              </tr>
            }
          }
        </tbody>
      </table>
    </div>
  `,
  styleUrl: './encargado-movimientos.scss',
})
export class EncargadoMovimientos implements OnInit {
  private inventarioService = inject(InventarioService);

  movimientos = signal<MovimientoInventario[]>([]);
  movimientosFiltrados = signal<MovimientoInventario[]>([]);
  cargando = signal<boolean>(false);

  toast = signal<string | null>(null);
  toastIsError = signal<boolean>(false);

  filtroTipo: 'todos' | 'entrada' | 'salida' | 'ajuste' = 'todos';
  terminoBusqueda = '';

  ngOnInit() {
    this.cargar();
  }

  cargar() {
    this.cargando.set(true);
    const tipo = this.filtroTipo === 'todos' ? undefined : this.filtroTipo;

    this.inventarioService.listarMovimientos({ tipo }).subscribe({
      next: (data) => {
        this.movimientos.set(data);
        this.filtrar();
        this.cargando.set(false);
      },
      error: (err) => {
        console.error('Error cargando movimientos', err);
        this.mostrarToast('Error al cargar historial de movimientos', true);
        this.cargando.set(false);
      },
    });
  }

  setFiltroTipo(tipo: 'todos' | 'entrada' | 'salida' | 'ajuste') {
    this.filtroTipo = tipo;
    this.cargar();
  }

  filtrar() {
    let list = this.movimientos();

    if (this.terminoBusqueda.trim()) {
      const q = this.terminoBusqueda.toLowerCase();
      list = list.filter(
        (m) =>
          (m.nombre_producto && m.nombre_producto.toLowerCase().includes(q)) ||
          (m.motivo && m.motivo.toLowerCase().includes(q)) ||
          (m.nombre_usuario && m.nombre_usuario.toLowerCase().includes(q))
      );
    }

    this.movimientosFiltrados.set(list);
  }

  badgeClass(tipo: string): string {
    switch (tipo?.toLowerCase()) {
      case 'entrada':
        return 'badge-success';
      case 'salida':
        return 'badge-danger';
      case 'ajuste':
        return 'badge-info';
      default:
        return 'badge-muted';
    }
  }

  cantidadClass(tipo: string): string {
    switch (tipo?.toLowerCase()) {
      case 'entrada':
        return 'text-success';
      case 'salida':
        return 'text-danger';
      case 'ajuste':
        return 'text-info';
      default:
        return '';
    }
  }

  formatoCantidad(m: MovimientoInventario): string {
    if (m.tipo?.toLowerCase() === 'entrada') return `+${m.cantidad}`;
    if (m.tipo?.toLowerCase() === 'salida') return `-${m.cantidad}`;
    if (m.tipo?.toLowerCase() === 'ajuste') return m.cantidad > 0 ? `+${m.cantidad}` : `${m.cantidad}`;
    return `${m.cantidad}`;
  }

  private mostrarToast(mensaje: string, esError = false) {
    this.toast.set(mensaje);
    this.toastIsError.set(esError);
    setTimeout(() => this.toast.set(null), 3500);
  }
}
