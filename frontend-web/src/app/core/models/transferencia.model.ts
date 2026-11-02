export type EstadoTransferencia =
  | 'solicitada'
  | 'aprobada'
  | 'en_transito'
  | 'recibida'
  | 'rechazada'
  | 'cancelada';

export type AccionTransferencia = 'aprobar' | 'rechazar' | 'despachar' | 'recibir' | 'cancelar';

export interface TransferenciaItem {
  id: number;
  inventario_origen_id: number;
  producto_id: number;
  nombre_producto: string;
  nombre_talla: string | null;
  nombre_color: string | null;
  cantidad: number;
}

export interface TransferenciaHistorial {
  estado_anterior: EstadoTransferencia | null;
  estado_nuevo: EstadoTransferencia;
  nombre_usuario: string;
  comentario: string | null;
  creado_en: string;
}

export interface Transferencia {
  id: number;
  sucursal_origen_id: number;
  sucursal_destino_id: number;
  nombre_origen: string;
  nombre_destino: string;
  estado: EstadoTransferencia;
  motivo: string | null;
  nombre_solicitante: string;
  total_unidades: number;
  creado_en: string;
  actualizado_en: string | null;
  items: TransferenciaItem[];
  historial: TransferenciaHistorial[];
  /** Acciones que el usuario actual puede ejecutar ahora. */
  acciones: AccionTransferencia[];
}

export interface TransferenciaCreate {
  sucursal_origen_id: number;
  sucursal_destino_id: number;
  motivo?: string | null;
  items: { inventario_id: number; cantidad: number }[];
}
