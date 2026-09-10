import { Component, OnInit, inject, signal, computed } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { HttpClient } from '@angular/common/http';
import { Router } from '@angular/router';

import { CatalogoService } from '../../core/services/catalogo.service';
import { SucursalesService } from '../../core/services/sucursales.service';
import { ReservasService } from '../../core/services/reservas.service';
import { AuthService } from '../../core/services/auth.service';

import {
  Categoria,
  Producto,
  ProductoDisponibilidad,
  DisponibilidadSucursal,
  DisponibilidadTallaColor,
} from '../../core/models/catalogo.model';
import { Sucursal } from '../../core/models/sucursal.model';
import { Reserva, ReservaCreate, ReservaItemCreate } from '../../core/models/reserva.model';
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
  private router = inject(Router);
  private catalogoService = inject(CatalogoService);
  private sucursalesService = inject(SucursalesService);
  private reservasService = inject(ReservasService);
  auth = inject(AuthService);

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

  // Modal y estado de Reserva (CU03)
  reservaModalAbierto = signal<boolean>(false);
  reservaItemSeleccionado = signal<{
    producto_id: number;
    nombre_producto: string;
    talla_id: number | null;
    nombre_talla: string | null;
    color_id: number | null;
    nombre_color: string | null;
    sucursal_id: number;
    nombre_sucursal: string;
    disponible: number;
  } | null>(null);
  reservaCantidad = signal<number>(1);
  reservaHorario = signal<string>('');
  reservaCreando = signal<boolean>(false);
  reservaToast = signal<string | null>(null);
  reservaToastIsError = signal<boolean>(false);

  private toastTimeout: ReturnType<typeof setTimeout> | null = null;

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

  // Métodos de Reserva (CU03)
  abrirReservaModal(
    producto: Producto,
    sucursal: DisponibilidadSucursal,
    item: DisponibilidadTallaColor
  ) {
    if (!this.auth.isLoggedIn()) {
      this.mostrarReservaToast('Debes iniciar sesión para reservar', true);
      this.router.navigate(['/login']);
      return;
    }

    this.reservaItemSeleccionado.set({
      producto_id: producto.id,
      nombre_producto: producto.nombre,
      talla_id: item.talla_id,
      nombre_talla: item.nombre_talla,
      color_id: item.color_id,
      nombre_color: item.nombre_color,
      sucursal_id: sucursal.sucursal_id,
      nombre_sucursal: sucursal.nombre_sucursal,
      disponible: item.cantidad_disponible,
    });
    this.reservaCantidad.set(1);
    this.reservaHorario.set('');
    this.reservaModalAbierto.set(true);
  }

  cerrarReservaModal() {
    this.reservaModalAbierto.set(false);
    this.reservaItemSeleccionado.set(null);
    this.reservaCantidad.set(1);
    this.reservaHorario.set('');
    this.reservaCreando.set(false);
  }

  confirmarReserva() {
    const item = this.reservaItemSeleccionado();
    if (!item) return;

    const cantidad = this.reservaCantidad();
    if (cantidad < 1) {
      this.mostrarReservaToast('La cantidad debe ser al menos 1', true);
      return;
    }
    if (cantidad > item.disponible) {
      this.mostrarReservaToast(`Solo hay ${item.disponible} unidades disponibles`, true);
      return;
    }

    this.reservaCreando.set(true);

    const payload: ReservaCreate = {
      sucursal_id: item.sucursal_id,
      horario_aproximado: this.reservaHorario()
        ? new Date(this.reservaHorario()).toISOString()
        : null,
      items: [
        {
          producto_id: item.producto_id,
          talla_id: item.talla_id,
          color_id: item.color_id,
          cantidad: cantidad,
        },
      ],
    };

    this.reservasService.crear(payload).subscribe({
      next: (reserva) => {
        this.reservaCreando.set(false);
        this.mostrarReservaToast(`¡Reserva #${reserva.id} creada con éxito!`, false);
        this.cerrarReservaModal();
        if (this.selectedProducto()) {
          this.abrirDetalle(this.selectedProducto()!);
        }
        this.cargarProductos();
      },
      error: (err) => {
        this.reservaCreando.set(false);
        const errorMsg = err.error?.detail || 'Error al procesar la reserva';
        this.mostrarReservaToast(errorMsg, true);
      },
    });
  }

  mostrarReservaToast(msg: string, isError = false) {
    if (this.toastTimeout) {
      clearTimeout(this.toastTimeout);
    }
    this.reservaToast.set(msg);
    this.reservaToastIsError.set(isError);
    this.toastTimeout = setTimeout(() => {
      this.reservaToast.set(null);
    }, 3500);
  }
}
