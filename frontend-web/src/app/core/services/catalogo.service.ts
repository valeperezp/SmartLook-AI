import { Injectable, inject } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { environment } from '../../../environments/environment';
import {
  Categoria,
  Color,
  Coleccion,
  Producto,
  ProductoCreate,
  Talla,
  Temporada,
} from '../models/catalogo.model';

@Injectable({ providedIn: 'root' })
export class CatalogoService {
  private http = inject(HttpClient);
  private readonly base = `${environment.apiUrl}/catalogo`;

  // Categorías
  listarCategorias() {
    return this.http.get<Categoria[]>(`${this.base}/categorias`);
  }
  crearCategoria(nombre: string) {
    return this.http.post<Categoria>(`${this.base}/categorias`, { nombre });
  }
  eliminarCategoria(id: number) {
    return this.http.delete<Categoria>(`${this.base}/categorias/${id}`);
  }

  // Tallas
  listarTallas() {
    return this.http.get<Talla[]>(`${this.base}/tallas`);
  }
  crearTalla(nombre: string) {
    return this.http.post<Talla>(`${this.base}/tallas`, { nombre });
  }
  eliminarTalla(id: number) {
    return this.http.delete<Talla>(`${this.base}/tallas/${id}`);
  }

  // Colores
  listarColores() {
    return this.http.get<Color[]>(`${this.base}/colores`);
  }
  crearColor(nombre: string, hex?: string) {
    return this.http.post<Color>(`${this.base}/colores`, { nombre, hex });
  }
  eliminarColor(id: number) {
    return this.http.delete<Color>(`${this.base}/colores/${id}`);
  }

  // Temporadas
  listarTemporadas() {
    return this.http.get<Temporada[]>(`${this.base}/temporadas`);
  }
  crearTemporada(nombre: string) {
    return this.http.post<Temporada>(`${this.base}/temporadas`, { nombre });
  }
  eliminarTemporada(id: number) {
    return this.http.delete<Temporada>(`${this.base}/temporadas/${id}`);
  }

  // Colecciones
  listarColecciones() {
    return this.http.get<Coleccion[]>(`${this.base}/colecciones`);
  }
  crearColeccion(nombre: string, temporada_id?: number) {
    return this.http.post<Coleccion>(`${this.base}/colecciones`, { nombre, temporada_id });
  }
  eliminarColeccion(id: number) {
    return this.http.delete<Coleccion>(`${this.base}/colecciones/${id}`);
  }

  // Productos
  listarProductos(incluirInactivos = false) {
    return this.http.get<Producto[]>(`${this.base}/productos`, {
      params: { incluir_inactivos: incluirInactivos },
    });
  }
  crearProducto(data: ProductoCreate) {
    return this.http.post<Producto>(`${this.base}/productos`, data);
  }
  actualizarProducto(id: number, data: Partial<ProductoCreate>) {
    return this.http.put<Producto>(`${this.base}/productos/${id}`, data);
  }
  eliminarProducto(id: number) {
    return this.http.delete<Producto>(`${this.base}/productos/${id}`);
  }
}
