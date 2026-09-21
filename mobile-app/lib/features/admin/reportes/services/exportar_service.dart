import 'package:dio/dio.dart';
import '../../../../core/network/dio_client.dart';
import 'file_saver/file_saver.dart';

class ExportarService {
  final DioClient _client = DioClient();

  /// Descarga el reporte en PDF o Excel y lo abre/descarga según la plataforma
  Future<String> exportarReporte({
    required String tipo, // 'pdf' o 'excel'
    int? sucursalId,
  }) async {
    final query = <String, dynamic>{};
    if (sucursalId != null) {
      query['sucursal_id'] = sucursalId;
    }

    final endpoint = '/reportes/exportar/$tipo';
    final response = await _client.dio.get<List<int>>(
      endpoint,
      queryParameters: query,
      options: Options(responseType: ResponseType.bytes),
    );

    final bytes = response.data;
    if (bytes == null || bytes.isEmpty) {
      throw Exception('El archivo descargado está vacío');
    }

    final ext = tipo == 'pdf' ? 'pdf' : 'xlsx';
    final mime = tipo == 'pdf'
        ? 'application/pdf'
        : 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final nombreArchivo = 'reporte_smartlook_$timestamp.$ext';

    return await FileSaver.saveAndOpenFile(
      bytes: bytes,
      fileName: nombreArchivo,
      mimeType: mime,
    );
  }
}
