import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/network/dio_client.dart';
import '../models/sucursal_qr.dart';

class SucursalQrService {
  final DioClient _client = DioClient();

  /// Obtiene el código QR activo de una sucursal.
  /// Si no existe (404), retorna null.
  Future<SucursalQR?> obtenerQR(int sucursalId) async {
    try {
      final response = await _client.get('/sucursales/$sucursalId/qr');
      if (response.data is Map<String, dynamic>) {
        return SucursalQR.fromJson(response.data as Map<String, dynamic>);
      }
      return null;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return null;
      }
      rethrow;
    } catch (_) {
      return null;
    }
  }

  /// Sube un nuevo código QR para la sucursal (reemplaza cualquier anterior).
  Future<SucursalQR> subirQR(int sucursalId, XFile archivo) async {
    final bytes = await archivo.readAsBytes();
    final formData = FormData.fromMap({
      'archivo': MultipartFile.fromBytes(
        bytes,
        filename: archivo.name.isNotEmpty ? archivo.name : 'qr_sucursal.png',
      ),
    });

    final response = await _client.post(
      '/sucursales/$sucursalId/qr',
      data: formData,
    );

    if (response.data == null) {
      throw Exception('Error al subir el código QR');
    }

    return SucursalQR.fromJson(response.data as Map<String, dynamic>);
  }

  /// Desactiva el código QR actualmente activo de la sucursal.
  Future<void> desactivarQR(int sucursalId) async {
    await _client.delete('/sucursales/$sucursalId/qr');
  }
}
