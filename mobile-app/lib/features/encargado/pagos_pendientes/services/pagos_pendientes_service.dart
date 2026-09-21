import '../../../../core/network/dio_client.dart';
import '../../../checkout/models/pago.dart';

class PagosPendientesService {
  final DioClient _client = DioClient();

  /// Lista pagos QR que están pendientes de verificación.
  Future<List<Pago>> listarPendientes({int? sucursalId}) async {
    final query = <String, dynamic>{};
    if (sucursalId != null) {
      query['sucursal_id'] = sucursalId;
    }

    final response = await _client.get(
      '/pagos/pendientes-verificacion',
      query: query.isNotEmpty ? query : null,
    );

    if (response.data is List) {
      return (response.data as List)
          .map((json) => Pago.fromJson(json as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  /// Aprueba o rechaza un pago QR por parte del encargado o cajero.
  Future<Pago> confirmarQR({
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
      throw Exception('Error al actualizar estado del pago QR');
    }

    return Pago.fromJson(response.data as Map<String, dynamic>);
  }
}
