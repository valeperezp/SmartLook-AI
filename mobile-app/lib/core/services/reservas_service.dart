import '../models/reserva.dart';
import '../network/dio_client.dart';

class ReservasService {
  final DioClient _dioClient = DioClient();

  Future<Reserva> crear(ReservaCreate data) async {
    final response = await _dioClient.post(
      '/reservas',
      data: data.toJson(),
    );
    return Reserva.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<Reserva>> misReservas() async {
    final response = await _dioClient.get('/reservas/mis-reservas');
    if (response.data is List) {
      return (response.data as List)
          .map((json) => Reserva.fromJson(json as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  Future<Reserva> obtener(int id) async {
    final response = await _dioClient.get('/reservas/$id');
    return Reserva.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Reserva> cancelar(int id) async {
    final response = await _dioClient.patch('/reservas/$id/cancelar');
    return Reserva.fromJson(response.data as Map<String, dynamic>);
  }
}
