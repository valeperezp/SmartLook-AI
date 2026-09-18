import '../network/dio_client.dart';

class EncargadoService {
  final DioClient _dioClient = DioClient();

  /// Obtiene el resumen de inventario de la sucursal del encargado.
  Future<Map<String, dynamic>> obtenerResumen() async {
    final response = await _dioClient.get('/inventario/resumen');
    return response.data as Map<String, dynamic>;
  }

  /// Lista los registros de inventario de la sucursal asignada.
  Future<List<dynamic>> listarInventarioMiSucursal() async {
    final response = await _dioClient.get('/inventario/mi-sucursal');
    if (response.data is List) {
      return response.data as List<dynamic>;
    }
    return [];
  }

  /// Lista el historial de movimientos de la sucursal.
  Future<List<dynamic>> listarMovimientos() async {
    final response = await _dioClient.get('/inventario/movimientos');
    if (response.data is List) {
      return response.data as List<dynamic>;
    }
    return [];
  }

  /// Lista las reservas asociadas a la sucursal del encargado.
  Future<List<dynamic>> listarMisReservas() async {
    final response = await _dioClient.get('/reservas/mi-sucursal');
    if (response.data is List) {
      return response.data as List<dynamic>;
    }
    return [];
  }

  /// Registra una entrada o salida de inventario.
  Future<dynamic> crearMovimiento(Map<String, dynamic> data) async {
    final response = await _dioClient.post('/inventario/movimientos', data: data);
    return response.data;
  }

  /// Realiza un ajuste de stock para un registro de inventario.
  Future<dynamic> crearAjuste(Map<String, dynamic> data) async {
    final response = await _dioClient.post('/inventario/ajuste', data: data);
    return response.data;
  }

  /// Actualiza el umbral de stock mínimo para alertas.
  Future<dynamic> actualizarStockMinimo(int id, int stockMinimo) async {
    final response = await _dioClient.patch(
      '/inventario/$id/stock-minimo',
      data: {'stock_minimo': stockMinimo},
    );
    return response.data;
  }

  /// Cambia el estado de una reserva en la sucursal.
  Future<dynamic> cambiarEstadoReserva(int reservaId, String nuevoEstado) async {
    final response = await _dioClient.patch(
      '/reservas/$reservaId/estado?nuevo_estado=$nuevoEstado',
      data: {},
    );
    return response.data;
  }

  /// Obtiene el detalle completo de una reserva de la sucursal.
  Future<dynamic> obtenerDetalleReserva(int id) async {
    final response = await _dioClient.get('/reservas/detalle/$id');
    return response.data;
  }

  /// Lista las alertas de stock bajo o agotados en la sucursal.
  Future<List<dynamic>> listarAlertas() async {
    final response = await _dioClient.get('/inventario/alertas');
    if (response.data is List) {
      return response.data as List<dynamic>;
    }
    return [];
  }
}
