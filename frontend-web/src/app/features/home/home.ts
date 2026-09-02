import { Component, OnInit, inject, signal, computed } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { HttpClient } from '@angular/common/http';
import { CatalogoService } from '../../core/services/catalogo.service';
import { Categoria, Producto } from '../../core/models/catalogo.model';
import { environment } from '../../../environments/environment';

@Component({
  selector: 'app-home',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './home.html',
  styleUrl: './home.scss',
})
export class Home implements OnInit {
  private http = inject(HttpClient);
  private catalogoService = inject(CatalogoService);

  backendStatus = signal<'checking' | 'connected' | 'error'>('checking');
  productos = signal<Producto[]>([]);
  categorias = signal<Categoria[]>([]);
  isLoading = signal<boolean>(true);
  selectedCategoryId = signal<number | 'todos'>('todos');
  searchQuery = signal<string>('');

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

  cargarProductos() {
    this.isLoading.set(true);
    this.catalogoService.listarProductos().subscribe({
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
}
