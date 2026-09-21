import '../../../../core/network/dio_client.dart';
import '../models/reporte_models.dart';

class ReportesService {
  final DioClient _client = DioClient();

  /// Obtiene el resumen general de reportes (KPIs y métricas).
  Future<ResumenReportes> resumen({int? sucursalId}) async {
    final query = <String, dynamic>{};
    if (sucursalId != null) {
      query['sucursal_id'] = sucursalId;
    }

    final response = await _client.get('/reportes/resumen', query: query);
    return ResumenReportes.fromJson(response.data as Map<String, dynamic>);
  }

  /// Obtiene las reservas agrupadas por día para gráficos temporales.
  Future<List<ReservasPorDia>> reservasPorDia({
    int? sucursalId,
    int dias = 14,
  }) async {
    final query = <String, dynamic>{'dias': dias};
    if (sucursalId != null) {
      query['sucursal_id'] = sucursalId;
    }

    final response = await _client.get('/reportes/reservas-por-dia', query: query);
    final list = response.data as List<dynamic>? ?? [];
    return list
        .map((e) => ReservasPorDia.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Obtiene la distribución de reservas por sucursal (solo admin).
  Future<List<ReservasPorSucursal>> reservasPorSucursal() async {
    final response = await _client.get('/reportes/reservas-por-sucursal');
    final list = response.data as List<dynamic>? ?? [];
    return list
        .map((e) => ReservasPorSucursal.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Obtiene las reservas agrupadas por estado (pendiente, confirmada, cancelada, etc.).
  Future<List<ReservasPorEstado>> reservasPorEstado({int? sucursalId}) async {
    final query = <String, dynamic>{};
    if (sucursalId != null) {
      query['sucursal_id'] = sucursalId;
    }

    final response =
        await _client.get('/reportes/reservas-por-estado', query: query);
    final list = response.data as List<dynamic>? ?? [];
    return list
        .map((e) => ReservasPorEstado.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
