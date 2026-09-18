import { Component, OnInit, inject, signal, computed } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { IconComponent } from '../../../core/components/icon/icon';
import { PromocionesService } from '../../../core/services/promociones.service';
import { CatalogoService } from '../../../core/services/catalogo.service';
import { Promocion, PromocionCreate, PromocionUpdate } from '../../../core/models/promocion.model';
import { Producto, Categoria } from '../../../core/models/catalogo.model';

@Component({
  selector: 'app-promociones-admin',
  standalone: true,
  imports: [CommonModule, FormsModule, IconComponent],
  templateUrl: './promociones-admin.html',
  styleUrl: './promociones-admin.scss',
})
export class PromocionesAdmin implements OnInit {
  private service = inject(PromocionesService);
  private catalogoService = inject(CatalogoService);

  promociones = signal<Promocion[]>([]);
  productos = signal<Producto[]>([]);
  categorias = signal<Categoria[]>([]);
  cargando = signal<boolean>(true);
  errorCarga = signal<boolean>(false);
  guardando = signal<boolean>(false);
  busqueda = signal<string>('');
  filtroEstado = signal<'todas' | 'activas' | 'inactivas'>('todas');

  // Modal crear / editar
  modalAbierto = signal<boolean>(false);
  promocionEditando = signal<Promocion | null>(null);
  form = signal<{
    nombre: string;
    descripcion: string;
    tipo: 'porcentaje' | 'monto_fijo';
    valor: number | null;
    fecha_inicio: string;
    fecha_fin: string;
    producto_ids: number[];
  }>({
    nombre: '',
    descripcion: '',
    tipo: 'porcentaje',
    valor: null,
    fecha_inicio: '',
    fecha_fin: '',
    producto_ids: [],
  });

  // Modal gestionar productos
  modalProductosAbierto = signal<boolean>(false);
  promocionProductos = signal<Promocion | null>(null);
  productosSeleccionados = signal<Set<number>>(new Set());
  busquedaProductos = signal<string>('');

  // Toast
  toast = signal<string | null>(null);
  toastIsError = signal<boolean>(false);
  private toastTimer: any = null;

  promocionesFiltradas = computed(() => {
    let list = this.promociones();
    const estado = this.filtroEstado();
    if (estado === 'activas') {
      list = list.filter((p) => p.activo);
    } else if (estado === 'inactivas') {
      list = list.filter((p) => !p.activo);
    }

    const q = this.busqueda().trim().toLowerCase();
    if (q) {
      list = list.filter(
        (p) =>
          p.nombre.toLowerCase().includes(q) ||
          (p.descripcion && p.descripcion.toLowerCase().includes(q))
      );
    }
    return list;
  });

  productosFiltradosModal = computed(() => {
    const q = this.busquedaProductos().trim().toLowerCase();
    const list = this.productos();
    if (!q) return list;
    return list.filter(
      (p) =>
        p.nombre.toLowerCase().includes(q) ||
        (p.categoria && p.categoria.nombre.toLowerCase().includes(q))
    );
  });

  ngOnInit() {
    this.cargar();
    this.cargarProductos();
    this.cargarCategorias();
  }

  cargar() {
    this.cargando.set(true);
    this.errorCarga.set(false);
    this.service.listar(false).subscribe({
      next: (data) => {
        this.promociones.set(data);
        this.cargando.set(false);
      },
      error: (err) => {
        console.error('Error al listar promociones:', err);
        this.errorCarga.set(true);
        this.cargando.set(false);
      },
    });
  }

  cargarProductos() {
    this.catalogoService.listarProductos(true).subscribe({
      next: (data) => this.productos.set(data),
      error: (err) => console.error('Error al listar productos:', err),
    });
  }

  cargarCategorias() {
    this.catalogoService.listarCategorias().subscribe({
      next: (data) => this.categorias.set(data),
      error: (err) => console.error('Error al listar categorias:', err),
    });
  }

  abrirModalCrear() {
    const today = new Date().toISOString().split('T')[0];
    const nextMonth = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString().split('T')[0];

    this.form.set({
      nombre: '',
      descripcion: '',
      tipo: 'porcentaje',
      valor: null,
      fecha_inicio: today,
      fecha_fin: nextMonth,
      producto_ids: [],
    });
    this.promocionEditando.set(null);
    this.modalAbierto.set(true);
  }

  abrirModalEditar(promocion: Promocion) {
    this.promocionEditando.set(promocion);
    this.form.set({
      nombre: promocion.nombre,
      descripcion: promocion.descripcion || '',
      tipo: promocion.tipo,
      valor: promocion.valor,
      fecha_inicio: promocion.fecha_inicio,
      fecha_fin: promocion.fecha_fin,
      producto_ids: promocion.productos ? promocion.productos.map((p) => p.producto_id) : [],
    });
    this.modalAbierto.set(true);
  }

  cerrarModal() {
    this.modalAbierto.set(false);
    this.promocionEditando.set(null);
  }

  guardar() {
    const f = this.form();
    if (!f.nombre.trim()) {
      this.mostrarToast('El nombre de la promoción es obligatorio', true);
      return;
    }
    if (f.valor === null || f.valor <= 0) {
      this.mostrarToast('El valor de la promoción debe ser mayor a 0', true);
      return;
    }
    if (f.tipo === 'porcentaje' && f.valor > 100) {
      this.mostrarToast('El porcentaje de descuento no puede ser mayor a 100%', true);
      return;
    }
    if (!f.fecha_inicio || !f.fecha_fin) {
      this.mostrarToast('Las fechas de inicio y fin son obligatorias', true);
      return;
    }
    if (f.fecha_fin < f.fecha_inicio) {
      this.mostrarToast('La fecha de fin no puede ser anterior a la de inicio', true);
      return;
    }

    this.guardando.set(true);
    const editando = this.promocionEditando();

    if (editando) {
      const updateData: PromocionUpdate = {
        nombre: f.nombre.trim(),
        descripcion: f.descripcion.trim() || undefined,
        tipo: f.tipo,
        valor: Number(f.valor),
        fecha_inicio: f.fecha_inicio,
        fecha_fin: f.fecha_fin,
      };

      this.service.actualizar(editando.id, updateData).subscribe({
        next: () => {
          this.guardando.set(false);
          this.cerrarModal();
          this.mostrarToast('Promoción actualizada con éxito');
          this.cargar();
        },
        error: (err) => {
          console.error('Error al actualizar promoción:', err);
          this.guardando.set(false);
          const msg = err.error?.detail || 'Error al actualizar promoción';
          this.mostrarToast(msg, true);
        },
      });
    } else {
      const createData: PromocionCreate = {
        nombre: f.nombre.trim(),
        descripcion: f.descripcion.trim() || undefined,
        tipo: f.tipo,
        valor: Number(f.valor),
        fecha_inicio: f.fecha_inicio,
        fecha_fin: f.fecha_fin,
        producto_ids: [],
      };

      this.service.crear(createData).subscribe({
        next: () => {
          this.guardando.set(false);
          this.cerrarModal();
          this.mostrarToast('Promoción creada con éxito');
          this.cargar();
        },
        error: (err) => {
          console.error('Error al crear promoción:', err);
          this.guardando.set(false);
          const msg = err.error?.detail || 'Error al crear promoción';
          this.mostrarToast(msg, true);
        },
      });
    }
  }

  desactivar(promocion: Promocion) {
    if (!confirm(`¿Desactivar la promoción "${promocion.nombre}"?`)) {
      return;
    }
    this.service.desactivar(promocion.id).subscribe({
      next: () => {
        this.mostrarToast('Promoción desactivada');
        this.cargar();
      },
      error: (err) => {
        console.error('Error al desactivar:', err);
        this.mostrarToast(err.error?.detail || 'Error al desactivar la promoción', true);
      },
    });
  }

  reactivar(promocion: Promocion) {
    if (!confirm(`¿Reactivar la promoción "${promocion.nombre}"?`)) {
      return;
    }
    this.service.reactivar(promocion.id).subscribe({
      next: () => {
        this.mostrarToast('Promoción reactivada con éxito');
        this.cargar();
      },
      error: (err) => {
        console.error('Error al reactivar:', err);
        this.mostrarToast(err.error?.detail || 'Error al reactivar la promoción', true);
      },
    });
  }

  abrirModalProductos(promocion: Promocion) {
    this.promocionProductos.set(promocion);
    const selected = new Set<number>();
    if (promocion.productos) {
      promocion.productos.forEach((p) => selected.add(p.producto_id));
    }
    this.productosSeleccionados.set(selected);
    this.busquedaProductos.set('');
    this.modalProductosAbierto.set(true);
  }

  cerrarModalProductos() {
    this.modalProductosAbierto.set(false);
    this.promocionProductos.set(null);
  }

  toggleProducto(productoId: number) {
    const s = new Set(this.productosSeleccionados());
    if (s.has(productoId)) {
      s.delete(productoId);
    } else {
      s.add(productoId);
    }
    this.productosSeleccionados.set(s);
  }

  guardarProductos() {
    const promo = this.promocionProductos();
    if (!promo) return;

    this.guardando.set(true);
    const ids = Array.from(this.productosSeleccionados());

    this.service.actualizarProductos(promo.id, ids).subscribe({
      next: () => {
        this.guardando.set(false);
        this.cerrarModalProductos();
        this.mostrarToast('Productos actualizados en la promoción');
        this.cargar();
      },
      error: (err) => {
        console.error('Error al actualizar productos:', err);
        this.guardando.set(false);
        this.mostrarToast(err.error?.detail || 'Error al actualizar productos', true);
      },
    });
  }

  calcularPrecioConDescuento(precioOriginal: number, promocion: Promocion | null): number {
    if (!promocion) return precioOriginal;
    let final = precioOriginal;
    if (promocion.tipo === 'porcentaje') {
      final = precioOriginal * (1 - promocion.valor / 100);
    } else {
      final = precioOriginal - promocion.valor;
    }
    return Math.max(0, Math.round(final * 100) / 100);
  }

  formatearValor(promocion: Promocion): string {
    if (promocion.tipo === 'porcentaje') {
      return `${promocion.valor}%`;
    }
    return `$${Number(promocion.valor).toFixed(2)}`;
  }

  formatearFecha(fechaStr: string): string {
    if (!fechaStr) return '';
    const parts = fechaStr.split('-');
    if (parts.length === 3) {
      return `${parts[2]}/${parts[1]}/${parts[0]}`;
    }
    return fechaStr;
  }

  mostrarToast(msg: string, isError: boolean = false) {
    if (this.toastTimer) {
      clearTimeout(this.toastTimer);
    }
    this.toast.set(msg);
    this.toastIsError.set(isError);
    this.toastTimer = setTimeout(() => {
      this.toast.set(null);
    }, 3500);
  }
}
