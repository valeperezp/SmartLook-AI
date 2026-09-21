import '../../../../core/network/dio_client.dart';
import '../../../checkout/models/pago.dart';
import '../../../encargado/mi_qr/models/sucursal_qr.dart';

class QrCajeroService {
  final DioClient _client = DioClient();

  /// Genera un nuevo registro de pago QR para la venta especificada.
  Future<Pago> generarPagoQR(int ventaId) async {
    final response = await _client.post(
      '/pagos/qr',
      data: {'venta_id': ventaId},
    );

    if (response.data == null) {
      throw Exception('Error al generar pago QR');
    }

    return Pago.fromJson(response.data as Map<String, dynamic>);
  }

  /// Consulta el estado actual de un pago.
  Future<Pago> consultarPago(int pagoId) async {
    final response = await _client.get('/pagos/$pagoId');
    if (response.data == null) {
      throw Exception('Pago no encontrado');
    }
    return Pago.fromJson(response.data as Map<String, dynamic>);
  }

  /// Confirma o rechaza el comprobante de un pago QR.
  Future<Pago> confirmarCobroQR({
    required int pagoId,
    required bool aprobar,
    String? motivo,
  }) async {
    final data = <String, dynamic>{
      'aprobar': aprobar,
    };
    if (motivo != null && motivo.trim().isNotEmpty) {
      data['motivo_rechazo'] = motivo.trim();
    }

    final response = await _client.patch(
      '/pagos/$pagoId/confirmar-qr',
      data: data,
    );

    if (response.data == null) {
      throw Exception('Error al actualizar estado del cobro QR');
    }

    return Pago.fromJson(response.data as Map<String, dynamic>);
  }

  /// Obtiene el QR activo de la sucursal (si está configurado).
  Future<SucursalQR?> obtenerQrSucursal(int sucursalId) async {
    try {
      final response = await _client.get('/sucursales/$sucursalId/qr');
      if (response.data is Map<String, dynamic>) {
        return SucursalQR.fromJson(response.data as Map<String, dynamic>);
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
