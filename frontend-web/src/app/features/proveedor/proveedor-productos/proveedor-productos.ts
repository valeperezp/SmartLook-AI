import { Component, OnInit, inject, signal, computed } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { IconComponent } from '../../../core/components/icon/icon';
import { CatalogoService } from '../../../core/services/catalogo.service';
import {
  Categoria,
  Coleccion,
  Producto,
  ProductoCreate,
  Temporada,
} from '../../../core/models/catalogo.model';

@Component({
  selector: 'app-proveedor-productos',
  standalone: true,
  imports: [CommonModule, FormsModule, IconComponent],
  templateUrl: './proveedor-productos.html',
  styleUrl: './proveedor-productos.scss',
})
export class ProveedorProductos implements OnInit {
  private catalogoService = inject(CatalogoService);

  productos = signal<Producto[]>([]);
  categorias = signal<Categoria[]>([]);
  temporadas = signal<Temporada[]>([]);
  colecciones = signal<Coleccion[]>([]);

  cargando = signal<boolean>(true);
  guardando = signal<boolean>(false);
  modalAbierto = signal<boolean>(false);
  productoEditando = signal<Producto | null>(null);

  toast = signal<string | null>(null);
  toastIsError = signal<boolean>(false);
  busqueda = signal<string>('');

  private toastTimeout: ReturnType<typeof setTimeout> | null = null;

  form: {
    nombre: string;
    descripcion: string;
    precio: number | null;
    categoria_id?: number;
    temporada_id?: number;
    coleccion_id?: number;
    modelo_ar_url: string;
  } = {
    nombre: '',
    descripcion: '',
    precio: null,
    categoria_id: undefined,
    temporada_id: undefined,
    coleccion_id: undefined,
    modelo_ar_url: '',
  };

  productosFiltrados = computed(() => {
    const q = this.busqueda().toLowerCase().trim();
    if (!q) return this.productos();
    return this.productos().filter(
      (p) =>
        p.nombre.toLowerCase().includes(q) ||
        (p.descripcion && p.descripcion.toLowerCase().includes(q)) ||
        (p.categoria && p.categoria.nombre.toLowerCase().includes(q))
    );
  });

  ngOnInit() {
    this.cargar();
    this.catalogoService.listarCategorias().subscribe((data) => this.categorias.set(data));
    this.catalogoService.listarTemporadas().subscribe((data) => this.temporadas.set(data));
    this.catalogoService.listarColecciones().subscribe((data) => this.colecciones.set(data));
  }

  cargar() {
    this.cargando.set(true);
    this.catalogoService.listarMisProductos(true).subscribe({
      next: (data) => {
        this.productos.set(data);
        this.cargando.set(false);
      },
      error: (err) => {
        this.cargando.set(false);
        this.mostrarToast(err?.error?.detail || 'Error al cargar tus productos', true);
      },
    });
  }

  abrirModalNuevo() {
    this.productoEditando.set(null);
    this.form = {
      nombre: '',
      descripcion: '',
      precio: null,
      categoria_id: this.categorias()[0]?.id,
      temporada_id: undefined,
      coleccion_id: undefined,
      modelo_ar_url: '',
    };
    this.modalAbierto.set(true);
  }

  abrirModalEditar(p: Producto) {
    this.productoEditando.set(p);
    this.form = {
      nombre: p.nombre,
      descripcion: p.descripcion || '',
      precio: p.precio,
      categoria_id: p.categoria_id,
      temporada_id: p.temporada_id || undefined,
      coleccion_id: p.coleccion_id || undefined,
      modelo_ar_url: p.modelo_ar_url || '',
    };
    this.modalAbierto.set(true);
  }

  cerrarModal() {
    this.modalAbierto.set(false);
    this.productoEditando.set(null);
  }

  guardar() {
    if (!this.form.nombre.trim()) {
      this.mostrarToast('El nombre del producto es obligatorio', true);
      return;
    }
    if (this.form.precio === null || this.form.precio < 0) {
      this.mostrarToast('Ingresa un precio válido mayor o igual a 0', true);
      return;
    }
    if (!this.form.categoria_id) {
      this.mostrarToast('Debes seleccionar una categoría', true);
      return;
    }

    this.guardando.set(true);

    const payload: ProductoCreate = {
      nombre: this.form.nombre.trim(),
      descripcion: this.form.descripcion.trim() || undefined,
      precio: Number(this.form.precio),
      categoria_id: Number(this.form.categoria_id),
      temporada_id: this.form.temporada_id ? Number(this.form.temporada_id) : undefined,
      coleccion_id: this.form.coleccion_id ? Number(this.form.coleccion_id) : undefined,
      modelo_ar_url: this.form.modelo_ar_url?.trim() || undefined,
    };

    const editando = this.productoEditando();

    if (editando) {
      this.catalogoService.actualizarMiProducto(editando.id, payload).subscribe({
        next: () => {
          this.guardando.set(false);
          this.cerrarModal();
          this.mostrarToast(`Producto "${payload.nombre}" actualizado con éxito`);
          this.cargar();
        },
        error: (err) => {
          this.guardando.set(false);
          this.mostrarToast(err?.error?.detail || 'Error al actualizar el producto', true);
        },
      });
    } else {
      this.catalogoService.crearMiProducto(payload).subscribe({
        next: () => {
          this.guardando.set(false);
          this.cerrarModal();
          this.mostrarToast(`Producto "${payload.nombre}" creado con éxito`);
          this.cargar();
        },
        error: (err) => {
          this.guardando.set(false);
          this.mostrarToast(err?.error?.detail || 'Error al crear el producto', true);
        },
      });
    }
  }

  desactivar(p: Producto) {
    if (!confirm(`¿Desactivar el producto "${p.nombre}"?`)) return;

    this.catalogoService.eliminarMiProducto(p.id).subscribe({
      next: () => {
        this.mostrarToast(`Producto "${p.nombre}" desactivado`);
        this.cargar();
      },
      error: (err) => {
        this.mostrarToast(err?.error?.detail || 'Error al desactivar el producto', true);
      },
    });
  }

  reactivar(p: Producto) {
    if (!confirm(`¿Reactivar el producto "${p.nombre}"?`)) return;
    this.guardando.set(true);
    this.catalogoService.actualizarMiProducto(p.id, { activo: true }).subscribe({
      next: () => {
        this.guardando.set(false);
        this.mostrarToast(`${p.nombre} reactivado`);
        this.cargar();
      },
      error: (err) => {
        this.guardando.set(false);
        this.mostrarToast(err?.error?.detail || 'Error al reactivar', true);
      },
    });
  }

  mostrarToast(msg: string, isError = false) {
    if (this.toastTimeout) {
      clearTimeout(this.toastTimeout);
    }
    this.toast.set(msg);
    this.toastIsError.set(isError);
    this.toastTimeout = setTimeout(() => {
      this.toast.set(null);
    }, 3500);
  }
}
