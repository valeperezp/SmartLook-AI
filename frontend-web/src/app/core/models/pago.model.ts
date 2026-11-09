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
  /** `pendiente_verificacion`: compra hecha sin conexión desde la app (ya trae su comprobante); el personal la aprueba o la rechaza. */
  estado: 'pendiente' | 'pendiente_verificacion' | 'completado' | 'fallido';
  referencia_externa: string | null;
  procesado_en: string;
  nombre_venta: string;
  monto_formateado: string;
  comprobante_path?: string | null;
  comprobante_url?: string | null;
  confirmado_por_id?: number | null;
  confirmado_en?: string | null;
}

/** Respuesta de `POST /pagos/{id}/verificar`. */
export interface PagoVerificado extends Pago {
  /** completada (al aprobar) | cancelada (al rechazar) */
  venta_estado: string | null;
  /** El reembolso pendiente que se creó al rechazar. */
  reembolso_id: number | null;
}
