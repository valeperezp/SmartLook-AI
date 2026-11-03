/** CU15 — Analítica con Machine Learning. */

export interface PuntoDemanda {
  fecha: string;
  unidades: number;
}

export interface DemandaCategoria {
  categoria: string;
  ultimos_30: number;
  proximos_30: number;
  variacion_pct: number | null;
}

export interface DemandaSerie {
  nombre: string;
  historico: PuntoDemanda[];
  prediccion: PuntoDemanda[];
  ultimos_30: number;
  proximos_30: number;
  variacion_pct: number | null;
  por_categoria: DemandaCategoria[];
  interpretacion: string;
}

export interface Segmento {
  segmento: string;
  clientes: number;
  pct_clientes: number;
  pct_ingresos: number;
  recencia_media: number | null;
  frecuencia_media: number | null;
  monto_medio: number | null;
  descripcion: string;
}

export interface ModeloInfo {
  tipo: 'demanda' | 'segmentacion';
  algoritmo: string;
  version: number;
  metricas: Record<string, any>;
  entrenado_en: string;
}

export interface Analitica {
  entrenado: boolean;
  modelos: ModeloInfo[];
  demanda: DemandaSerie | null;
  segmentos: { segmentos: Segmento[]; interpretacion: string } | null;
}
