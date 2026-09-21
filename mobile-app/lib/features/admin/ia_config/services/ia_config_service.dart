import '../../../../core/network/dio_client.dart';

class ConfiguracionIA {
  final String baseUrl;
  final String modelo;
  final bool apiKeyConfigurada;

  const ConfiguracionIA({
    required this.baseUrl,
    required this.modelo,
    required this.apiKeyConfigurada,
  });

  factory ConfiguracionIA.fromJson(Map<String, dynamic> json) {
    return ConfiguracionIA(
      baseUrl: json['base_url'] as String? ?? '',
      modelo: json['modelo'] as String? ?? '',
      apiKeyConfigurada: json['api_key_configurada'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'base_url': baseUrl,
        'modelo': modelo,
        'api_key_configurada': apiKeyConfigurada,
      };
}

class ResultadoPruebaIA {
  final bool ok;
  final String? respuesta;
  final String? error;

  const ResultadoPruebaIA({
    required this.ok,
    this.respuesta,
    this.error,
  });

  factory ResultadoPruebaIA.fromJson(Map<String, dynamic> json) {
    return ResultadoPruebaIA(
      ok: json['ok'] as bool? ?? false,
      respuesta: json['respuesta'] as String?,
      error: json['error'] as String?,
    );
  }
}

class IaConfigService {
  final DioClient _client = DioClient();

  /// Obtiene la configuración actual de la IA (admin).
  Future<ConfiguracionIA> obtenerConfig() async {
    final response = await _client.get('/ia/configuracion');
    return ConfiguracionIA.fromJson(response.data as Map<String, dynamic>);
  }

  /// Actualiza la configuración de la IA.
  Future<ConfiguracionIA> actualizarConfig(Map<String, dynamic> data) async {
    final response = await _client.put('/ia/configuracion', data: data);
    return ConfiguracionIA.fromJson(response.data as Map<String, dynamic>);
  }

  /// Prueba la conexión con el modelo configurado.
  Future<ResultadoPruebaIA> probarConexion() async {
    final response = await _client.post('/ia/configuracion/probar');
    return ResultadoPruebaIA.fromJson(response.data as Map<String, dynamic>);
  }
}
