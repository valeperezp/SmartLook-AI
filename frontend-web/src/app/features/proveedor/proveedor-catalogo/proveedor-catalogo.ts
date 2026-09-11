import { Component, OnInit, inject, signal, computed } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { IconComponent } from '../../../core/components/icon/icon';
import { CatalogoService } from '../../../core/services/catalogo.service';
import { Categoria, Producto } from '../../../core/models/catalogo.model';

@Component({
  selector: 'app-proveedor-catalogo',
  standalone: true,
  imports: [CommonModule, FormsModule, IconComponent],
  templateUrl: './proveedor-catalogo.html',
  styleUrl: './proveedor-catalogo.scss',
})
export class ProveedorCatalogo implements OnInit {
  private catalogoService = inject(CatalogoService);

  productos = signal<Producto[]>([]);
  categorias = signal<Categoria[]>([]);
  cargando = signal<boolean>(true);
  filtroCategoria = signal<number | 'todas'>('todas');
  busqueda = signal<string>('');

  productosFiltrados = computed(() => {
    const cat = this.filtroCategoria();
    const q = this.busqueda().toLowerCase().trim();

    return this.productos().filter((p) => {
      const matchCat = cat === 'todas' || p.categoria_id === cat;
      const matchBusqueda =
        !q ||
        p.nombre.toLowerCase().includes(q) ||
        (p.descripcion && p.descripcion.toLowerCase().includes(q)) ||
        (p.categoria && p.categoria.nombre.toLowerCase().includes(q));
      return matchCat && matchBusqueda;
    });
  });

  ngOnInit() {
    this.cargar();
    this.catalogoService.listarCategorias().subscribe((data) => this.categorias.set(data));
  }

  cargar() {
    this.cargando.set(true);
    this.catalogoService.listarProductos(true).subscribe({
      next: (data) => {
        this.productos.set(data);
        this.cargando.set(false);
      },
      error: () => {
        this.cargando.set(false);
      },
    });
  }

  setCategoria(id: number | 'todas') {
    this.filtroCategoria.set(id);
  }
}
