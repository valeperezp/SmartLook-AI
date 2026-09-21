class PaymentIntentCreate {
  final int ventaId;
  final String metodo;

  const PaymentIntentCreate({
    required this.ventaId,
    this.metodo = 'tarjeta',
  });

  Map<String, dynamic> toJson() => {
        'venta_id': ventaId,
        'metodo': metodo,
      };
}

class PaymentIntentResponse {
  final String clientSecret;
  final String paymentIntentId;
  final double monto;
  final String moneda;

  const PaymentIntentResponse({
    required this.clientSecret,
    required this.paymentIntentId,
    required this.monto,
    required this.moneda,
  });

  factory PaymentIntentResponse.fromJson(Map<String, dynamic> json) {
    return PaymentIntentResponse(
      clientSecret: json['client_secret'] as String? ?? '',
      paymentIntentId: json['payment_intent_id'] as String? ?? '',
      monto: (json['monto'] as num?)?.toDouble() ?? 0.0,
      moneda: json['moneda'] as String? ?? 'usd',
    );
  }
}

class Pago {
  final int id;
  final int ventaId;
  final String metodo;
  final double monto;
  final String estado; // 'pendiente' | 'completado' | 'fallido'
  final String? referenciaExterna;
  final DateTime procesadoEn;
  final String nombreVenta;
  final String montoFormateado;
  final String? comprobantePath;
  final String? comprobanteUrl;
  final int? confirmadoPorId;
  final DateTime? confirmadoEn;

  const Pago({
    required this.id,
    required this.ventaId,
    required this.metodo,
    required this.monto,
    required this.estado,
    this.referenciaExterna,
    required this.procesadoEn,
    required this.nombreVenta,
    required this.montoFormateado,
    this.comprobantePath,
    this.comprobanteUrl,
    this.confirmadoPorId,
    this.confirmadoEn,
  });

  factory Pago.fromJson(Map<String, dynamic> json) {
    DateTime parsedProcesado;
    try {
      parsedProcesado = DateTime.parse(json['procesado_en'] as String);
    } catch (_) {
      parsedProcesado = DateTime.now();
    }

    DateTime? parsedConfirmado;
    if (json['confirmado_en'] != null) {
      try {
        parsedConfirmado = DateTime.parse(json['confirmado_en'] as String);
      } catch (_) {
        parsedConfirmado = null;
      }
    }

    return Pago(
      id: json['id'] as int? ?? 0,
      ventaId: json['venta_id'] as int? ?? 0,
      metodo: json['metodo'] as String? ?? '',
      monto: (json['monto'] as num?)?.toDouble() ?? 0.0,
      estado: json['estado'] as String? ?? 'pendiente',
      referenciaExterna: json['referencia_externa'] as String?,
      procesadoEn: parsedProcesado,
      nombreVenta: json['nombre_venta'] as String? ?? '',
      montoFormateado: json['monto_formateado'] as String? ?? '',
      comprobantePath: json['comprobante_path'] as String?,
      comprobanteUrl: json['comprobante_url'] as String?,
      confirmadoPorId: json['confirmado_por_id'] as int?,
      confirmadoEn: parsedConfirmado,
    );
  }
}
