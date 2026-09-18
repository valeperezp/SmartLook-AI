export interface ItemCarrito {
  productoId: number;
  nombreProducto: string;
  precio: number;
  imagenUrl?: string;
  tallaId: number | null;
  nombreTalla: string | null;
  colorId: number | null;
  nombreColor: string | null;
  cantidad: number;
  maxDisponible?: number;
}
