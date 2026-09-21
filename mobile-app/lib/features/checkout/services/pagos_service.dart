import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/network/dio_client.dart';
import '../models/pago.dart';

class PagosService {
  final DioClient _client = DioClient();

  Future<PaymentIntentResponse> crearPaymentIntent({
    required int ventaId,
    String metodo = 'tarjeta',
  }) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/pagos/crear-intent',
      data: PaymentIntentCreate(ventaId: ventaId, metodo: metodo).toJson(),
    );

    if (response.data == null) {
      throw Exception('Error al obtener respuesta de payment intent');
    }

    return PaymentIntentResponse.fromJson(response.data!);
  }

  Future<Pago> confirmarPago({required String paymentIntentId}) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/pagos/confirmar',
      data: {'payment_intent_id': paymentIntentId},
    );

    if (response.data == null) {
      throw Exception('Error al confirmar pago');
    }

    return Pago.fromJson(response.data!);
  }

  Future<Pago> crearPagoQR({required int ventaId}) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/pagos/qr',
      data: {'venta_id': ventaId},
    );

    if (response.data == null) {
      throw Exception('Error al generar pago QR');
    }

    return Pago.fromJson(response.data!);
  }

  Future<Pago> subirComprobante({
    required int pagoId,
    required XFile archivo,
  }) async {
    final bytes = await archivo.readAsBytes();
    final formData = FormData.fromMap({
      'archivo': MultipartFile.fromBytes(
        bytes,
        filename: archivo.name.isNotEmpty ? archivo.name : 'comprobante.jpg',
      ),
    });

    final response = await _client.post<Map<String, dynamic>>(
      '/pagos/$pagoId/comprobante',
      data: formData,
    );

    if (response.data == null) {
      throw Exception('Error al subir comprobante');
    }

    return Pago.fromJson(response.data!);
  }

  Future<Pago> subirComprobanteBytes({
    required int pagoId,
    required Uint8List bytes,
    String nombreArchivo = 'comprobante.jpg',
  }) async {
    final formData = FormData.fromMap({
      'archivo': MultipartFile.fromBytes(
        bytes,
        filename: nombreArchivo,
      ),
    });

    final response = await _client.post<Map<String, dynamic>>(
      '/pagos/$pagoId/comprobante',
      data: formData,
    );

    if (response.data == null) {
      throw Exception('Error al subir comprobante');
    }

    return Pago.fromJson(response.data!);
  }

  Future<List<Pago>> obtenerPagoDeVenta(int ventaId) async {
    final response = await _client.get<List<dynamic>>('/pagos/venta/$ventaId');
    final list = response.data ?? [];
    return list.map((item) => Pago.fromJson(item as Map<String, dynamic>)).toList();
  }

  Future<Pago> obtenerPago(int pagoId) async {
    final response = await _client.get<Map<String, dynamic>>('/pagos/$pagoId');
    if (response.data == null) {
      throw Exception('Pago no encontrado');
    }
    return Pago.fromJson(response.data!);
  }
}
