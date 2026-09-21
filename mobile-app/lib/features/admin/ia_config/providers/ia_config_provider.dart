import 'package:flutter/foundation.dart';
import '../services/ia_config_service.dart';

class IaConfigProvider with ChangeNotifier {
  final IaConfigService _service = IaConfigService();

  ConfiguracionIA? _config;
  bool _isLoading = false;
  bool _isSaving = false;
  bool _isTesting = false;
  String? _errorMessage;
  ResultadoPruebaIA? _resultadoPrueba;

  // Getters
  ConfiguracionIA? get config => _config;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  bool get isTesting => _isTesting;
  String? get errorMessage => _errorMessage;
  ResultadoPruebaIA? get resultadoPrueba => _resultadoPrueba;

  /// Carga la configuración actual de la IA.
  Future<void> cargarConfig() async {
    _isLoading = true;
    _errorMessage = null;
    _resultadoPrueba = null;
    notifyListeners();

    try {
      _config = await _service.obtenerConfig();
      _isLoading = false;
      _errorMessage = null;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
    }
  }

  /// Guarda los cambios en la configuración.
  Future<bool> actualizarConfig({
    required String baseUrl,
    required String modelo,
    String? apiKey,
  }) async {
    _isSaving = true;
    _errorMessage = null;
    _resultadoPrueba = null;
    notifyListeners();

    try {
      final payload = <String, dynamic>{
        'base_url': baseUrl.trim(),
        'modelo': modelo.trim(),
      };
      if (apiKey != null && apiKey.trim().isNotEmpty) {
        payload['api_key'] = apiKey.trim();
      }

      _config = await _service.actualizarConfig(payload);
      _isSaving = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isSaving = false;
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  /// Prueba la conexión contra el LLM activo.
  Future<void> probarConexion() async {
    _isTesting = true;
    _resultadoPrueba = null;
    _errorMessage = null;
    notifyListeners();

    try {
      _resultadoPrueba = await _service.probarConexion();
      _isTesting = false;
      notifyListeners();
    } catch (e) {
      _isTesting = false;
      _resultadoPrueba = ResultadoPruebaIA(
        ok: false,
        error: e.toString().replaceAll('Exception: ', ''),
      );
      notifyListeners();
    }
  }

  void limpiarResultadoPrueba() {
    _resultadoPrueba = null;
    notifyListeners();
  }
}
