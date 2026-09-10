import { Component, OnInit, inject, signal, computed } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { HttpClient } from '@angular/common/http';
import { CatalogoService } from '../../core/services/catalogo.service';
import { SucursalesService } from '../../core/services/sucursales.service';
import { Categoria, Producto, ProductoDisponibilidad } from '../../core/models/catalogo.model';
import { Sucursal } from '../../core/models/sucursal.model';
import { environment } from '../../../environments/environment';
import { IconComponent } from '../../core/components/icon/icon';

@Component({
  selector: 'app-home',
  standalone: true,
  imports: [CommonModule, FormsModule, IconComponent],
  templateUrl: './home.html',
  styleUrl: './home.scss',
})
export class Home implements OnInit {
  private http = inject(HttpClient);
  private catalogoService = inject(CatalogoService);
  private sucursalesService = inject(SucursalesService);

  backendStatus = signal<'checking' | 'connected' | 'error'>('checking');
  productos = signal<Producto[]>([]);
  categorias = signal<Categoria[]>([]);
  sucursales = signal<Sucursal[]>([]);
  isLoading = signal<boolean>(true);
  selectedCategoryId = signal<number | 'todos'>('todos');
  selectedSucursalId = signal<number | 'todas'>('todas');
  searchQuery = signal<string>('');

  // Modal de detalle de disponibilidad
  modalAbierto = signal<boolean>(false);
  selectedProducto = signal<Producto | null>(null);
  disponibilidad = signal<ProductoDisponibilidad | null>(null);
  loadingDisponibilidad = signal<boolean>(false);
  errorDisponibilidad = signal<string | null>(null);

  filteredProductos = computed(() => {
    const catId = this.selectedCategoryId();
    const query = this.searchQuery().toLowerCase().trim();

    return this.productos().filter((p) => {
      const matchesCat = catId === 'todos' || p.categoria_id === catId;
      const matchesQuery =
        !query ||
        p.nombre.toLowerCase().includes(query) ||
        (p.descripcion && p.descripcion.toLowerCase().includes(query));
      return matchesCat && matchesQuery;
    });
  });

  ngOnInit() {
    this.checkBackendHealth();
    this.cargarCategorias();
    this.cargarSucursales();
    this.cargarProductos();
  }

  checkBackendHealth() {
    this.http.get<{ status: string }>(`${environment.apiUrl}/health`).subscribe({
      next: (res) => this.backendStatus.set(res.status === 'healthy' ? 'connected' : 'error'),
      error: () => this.backendStatus.set('error'),
    });
  }

  cargarCategorias() {
    this.catalogoService.listarCategorias().subscribe({
      next: (data) => this.categorias.set(data),
    });
  }

  cargarSucursales() {
    this.sucursalesService.listar().subscribe({
      next: (data) => this.sucursales.set(data.filter((s) => s.activa)),
    });
  }

  cargarProductos() {
    this.isLoading.set(true);
    const sucId =
      this.selectedSucursalId() === 'todas'
        ? undefined
        : Number(this.selectedSucursalId());

    this.catalogoService.listarProductos(false, sucId).subscribe({
      next: (data) => {
        this.productos.set(data);
        this.isLoading.set(false);
      },
      error: () => this.isLoading.set(false),
    });
  }

  setCategory(id: number | 'todos') {
    this.selectedCategoryId.set(id);
  }

  setSucursal(id: number | 'todas') {
    this.selectedSucursalId.set(id);
    this.cargarProductos();
  }

  abrirDetalle(producto: Producto) {
    this.selectedProducto.set(producto);
    this.modalAbierto.set(true);
    this.loadingDisponibilidad.set(true);
    this.errorDisponibilidad.set(null);
    this.disponibilidad.set(null);

    this.catalogoService.obtenerDisponibilidad(producto.id).subscribe({
      next: (data) => {
        this.disponibilidad.set(data);
        this.loadingDisponibilidad.set(false);
      },
      error: () => {
        this.errorDisponibilidad.set('No se pudo cargar la información de disponibilidad.');
        this.loadingDisponibilidad.set(false);
      },
    });
  }

  cerrarDetalle() {
    this.modalAbierto.set(false);
    this.selectedProducto.set(null);
    this.disponibilidad.set(null);
    this.errorDisponibilidad.set(null);
  }
}
