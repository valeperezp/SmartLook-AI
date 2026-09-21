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
  imagen_url: string | null;
  motivo: string;
  puntaje: number;
}

export interface ChatHistorialItem {
  autor: 'usuario' | 'bot';
  texto: string;
}

export interface ChatMensajeResponse {
  respuesta: string;
  intencion: string;
  sugerencias: string[];
}

export interface ConfiguracionIA {
  base_url: string;
  modelo: string;
  api_key_configurada: boolean;
}

export interface ConfiguracionIAUpdate {
  base_url: string;
  modelo: string;
  api_key?: string | null;
}

export interface ConfiguracionIAPrueba {
  ok: boolean;
  respuesta: string | null;
  error: string | null;
}

export interface ChatReportesResponse {
  respuesta: string;
  sugerencias: string[];
}
