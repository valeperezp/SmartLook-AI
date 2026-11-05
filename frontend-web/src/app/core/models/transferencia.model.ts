export type EstadoTransferencia =
  | 'solicitada'
  | 'aprobada' // solo en transferencias anteriores
  | 'en_transito'
  | 'recibida'
  | 'rechazada'
  | 'cancelada';

/** CU19: el origen envía o rechaza; el destino confirma la recepción o cancela antes del envío. */
export type AccionTransferencia = 'enviar' | 'rechazar' | 'recibir' | 'cancelar';

export interface TransferenciaItem {
  id: number;
  inventario_origen_id: number;
  producto_id: number;
  nombre_producto: string;
  nombre_talla: string | null;
  nombre_color: string | null;
  cantidad: number;
  /** Se completa al confirmar la recepción (8a: puede ser menor a lo enviado). */
  cantidad_recibida: number | null;
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
  /** Motivo del rechazo o diferencia entre lo enviado y lo recibido. */
  observacion: string | null;
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

/** CU19 paso 2: existencia de una prenda en otras sucursales. */
export interface DisponibilidadTransferencia {
  inventario_id: number;
  sucursal_id: number;
  nombre_sucursal: string;
  producto_id: number;
  nombre_producto: string;
  talla_id: number | null;
  nombre_talla: string | null;
  color_id: number | null;
  nombre_color: string | null;
  cantidad_disponible: number;
}
