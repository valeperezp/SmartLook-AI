import { Component, OnInit, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { IconComponent } from '../../../core/components/icon/icon';
import { InventarioService } from '../../../core/services/inventario.service';
import { SucursalesService } from '../../../core/services/sucursales.service';
import { CatalogoService } from '../../../core/services/catalogo.service';
import {
  AlertaStock,
  FiltrosInventario,
  InventarioItem,
  ResumenInventario,
} from '../../../core/models/inventario.model';
import { Sucursal } from '../../../core/models/sucursal.model';
import { Categoria } from '../../../core/models/catalogo.model';

@Component({
  selector: 'app-inventario-admin',
  standalone: true,
  imports: [CommonModule, FormsModule, IconComponent],
  templateUrl: './inventario-admin.html',
  styleUrl: './inventario-admin.scss',
})
export class InventarioAdmin implements OnInit {
  private inventarioService = inject(InventarioService);
  private sucursalesService = inject(SucursalesService);
  private catalogoService = inject(CatalogoService);

  inventario = signal<InventarioItem[]>([]);
  resumen = signal<ResumenInventario | null>(null);
  alertas = signal<AlertaStock[]>([]);
  sucursales = signal<Sucursal[]>([]);
  categorias = signal<Categoria[]>([]);

  cargando = signal<boolean>(false);
  mostrarAlertas = signal<boolean>(false);

  filtros: FiltrosInventario = {
    sucursal_id: undefined,
    categoria_id: undefined,
    solo_disponibles: false,
    solo_agotados: false,
  };

  ngOnInit() {
    this.cargarMetadatos();
    this.cargarResumen();
    this.cargarAlertas();
    this.aplicarFiltros();
  }

  cargarMetadatos() {
    this.sucursalesService.listar().subscribe({
      next: (data) => this.sucursales.set(data),
      error: (err) => console.error('Error cargando sucursales', err),
    });

    this.catalogoService.listarCategorias().subscribe({
      next: (data) => this.categorias.set(data),
      error: (err) => console.error('Error cargando categorías', err),
    });
  }

  cargarResumen() {
    this.inventarioService.resumen().subscribe({
      next: (data) => this.resumen.set(data),
      error: (err) => console.error('Error al cargar resumen de inventario', err),
    });
  }

  cargarAlertas() {
    this.inventarioService.alertas().subscribe({
      next: (data) => this.alertas.set(data),
      error: (err) => console.error('Error al cargar alertas de inventario', err),
    });
  }

  aplicarFiltros() {
    this.cargando.set(true);
    this.inventarioService.listar(this.filtros).subscribe({
      next: (data) => {
        this.inventario.set(data);
        this.cargando.set(false);
      },
      error: (err) => {
        console.error('Error al listar inventario', err);
        this.cargando.set(false);
      },
    });
  }

  onSoloDisponiblesChange() {
    if (this.filtros.solo_disponibles) {
      this.filtros.solo_agotados = false;
    }
    this.aplicarFiltros();
  }

  onSoloAgotadosChange() {
    if (this.filtros.solo_agotados) {
      this.filtros.solo_disponibles = false;
    }
    this.aplicarFiltros();
  }

  limpiarFiltros() {
    this.filtros = {
      sucursal_id: undefined,
      categoria_id: undefined,
      solo_disponibles: false,
      solo_agotados: false,
    };
    this.aplicarFiltros();
  }

  toggleAlertas() {
    this.mostrarAlertas.update((v) => !v);
  }
}
