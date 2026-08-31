import { Component, OnInit, inject, signal, computed } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { HttpClient } from '@angular/common/http';

export interface Producto {
  id?: number;
  nombre: string;
  descripcion?: string;
  categoria?: string;
  talla?: string;
  color?: string;
  temporada?: string;
  precio: number;
}

@Component({
  selector: 'app-root',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './app.html',
  styleUrl: './app.scss',
})
export class App implements OnInit {
  private http = inject(HttpClient);
  readonly apiUrl = 'http://localhost:8000';

  // Signals
  backendStatus = signal<'checking' | 'connected' | 'error'>('checking');
  productos = signal<Producto[]>([]);
  isLoading = signal<boolean>(true);
  selectedCategory = signal<string>('todos');
  searchQuery = signal<string>('');
  
  // Modal & notification states
  isModalOpen = signal<boolean>(false);
  isSaving = signal<boolean>(false);
  toastMessage = signal<string | null>(null);

  // New product form
  newProduct: Producto = {
    nombre: '',
    descripcion: '',
    categoria: 'Camisetas',
    talla: 'M',
    color: 'Negro',
    temporada: 'Primavera 2026',
    precio: 99.99
  };

  readonly categorias = ['todos', 'Camisetas', 'Pantalones', 'Vestidos', 'Chaquetas', 'Calzado', 'Accesorios'];

  // Filtered products computed signal
  filteredProductos = computed(() => {
    const cat = this.selectedCategory();
    const query = this.searchQuery().toLowerCase().trim();

    return this.productos().filter((p) => {
      const matchesCat = cat === 'todos' || p.categoria?.toLowerCase() === cat.toLowerCase();
      const matchesQuery =
        !query ||
        p.nombre.toLowerCase().includes(query) ||
        (p.descripcion && p.descripcion.toLowerCase().includes(query)) ||
        (p.color && p.color.toLowerCase().includes(query));
      return matchesCat && matchesQuery;
    });
  });

  ngOnInit() {
    this.checkBackendHealth();
    this.cargarProductos();
  }

  checkBackendHealth() {
    this.http.get<{ status: string }>(`${this.apiUrl}/health`).subscribe({
      next: (res) => {
        if (res.status === 'healthy') {
          this.backendStatus.set('connected');
        } else {
          this.backendStatus.set('error');
        }
      },
      error: () => {
        this.backendStatus.set('error');
      }
    });
  }

  cargarProductos() {
    this.isLoading.set(true);
    this.http.get<Producto[]>(`${this.apiUrl}/catalogo/productos`).subscribe({
      next: (data) => {
        this.productos.set(data);
        this.isLoading.set(false);
      },
      error: (err) => {
        console.error('Error cargando productos:', err);
        this.isLoading.set(false);
      }
    });
  }

  setCategory(cat: string) {
    this.selectedCategory.set(cat);
  }

  openCreateModal() {
    this.newProduct = {
      nombre: '',
      descripcion: '',
      categoria: 'Camisetas',
      talla: 'M',
      color: 'Negro',
      temporada: 'Primavera 2026',
      precio: 100.00
    };
    this.isModalOpen.set(true);
  }

  closeCreateModal() {
    this.isModalOpen.set(false);
  }

  guardarProducto() {
    if (!this.newProduct.nombre || this.newProduct.precio <= 0) {
      this.showToast('Por favor ingresa un nombre y precio válido');
      return;
    }

    this.isSaving.set(true);
    this.http.post<Producto>(`${this.apiUrl}/catalogo/productos`, this.newProduct).subscribe({
      next: (created) => {
        this.productos.update((prev) => [created, ...prev]);
        this.isSaving.set(false);
        this.closeCreateModal();
        this.showToast('¡Prenda agregada al catálogo con éxito!');
      },
      error: (err) => {
        console.error('Error guardando producto:', err);
        this.isSaving.set(false);
        this.showToast('Error al guardar el producto en el backend');
      }
    });
  }

  showToast(msg: string) {
    this.toastMessage.set(msg);
    setTimeout(() => {
      this.toastMessage.set(null);
    }, 4000);
  }
}
