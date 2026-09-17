export interface PreferenciaDetectada {
  tipo: 'categoria' | 'temporada' | 'coleccion';
  nombre: string;
  peso: number;
}

export interface PerfilPreferencias {
  tiene_historial: boolean;
  total_reservas_analizadas: number;
  preferencias: PreferenciaDetectada[];
}

export interface ProductoRecomendado {
  producto_id: number;
  nombre_producto: string;
  precio: number;
  nombre_categoria: string | null;
  modelo_ar_url: string | null;
  motivo: string;
  puntaje: number;
}
