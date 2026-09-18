export interface PaymentIntentCreate {
  venta_id: number;
  metodo?: string;
}

export interface PaymentIntentResponse {
  client_secret: string;
  payment_intent_id: string;
  monto: number;
  moneda: string;
}

export interface Pago {
  id: number;
  venta_id: number;
  metodo: string;
  monto: number;
  estado: 'pendiente' | 'completado' | 'fallido';
  referencia_externa: string | null;
  procesado_en: string;
  nombre_venta: string;
  monto_formateado: string;
  comprobante_path?: string | null;
  comprobante_url?: string | null;
  confirmado_por_id?: number | null;
  confirmado_en?: string | null;
}
