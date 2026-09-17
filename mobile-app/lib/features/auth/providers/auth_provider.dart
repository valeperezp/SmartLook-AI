import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import '../../../core/models/usuario.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/storage/token_storage.dart';

class AuthProvider extends ChangeNotifier {
  final DioClient _dioClient = DioClient();

  Usuario? _usuario;
  bool _isLoading = false;
  String? _errorMessage;
  bool _isInitialized = false;

  Usuario? get usuario => _usuario;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isInitialized => _isInitialized;

  bool get isLoggedIn => _usuario != null;
  bool get isAdmin => _usuario?.isAdmin ?? false;
  bool get isCliente => _usuario?.isCliente ?? false;
  bool get isEncargado => _usuario?.isEncargado ?? false;
  bool get isProveedor => _usuario?.isProveedor ?? false;

  AuthProvider() {
    cargarSesion();
  }

  Future<void> cargarSesion() async {
    _isLoading = true;
    notifyListeners();

    try {
      final hasToken = await TokenStorage.hasToken();
      if (hasToken) {
        final response = await _dioClient.get('/auth/me');
        if (response.statusCode == 200 && response.data != null) {
          _usuario = Usuario.fromJson(response.data as Map<String, dynamic>);
        } else {
          await TokenStorage.clearToken();
          _usuario = null;
        }
      } else {
        _usuario = null;
      }
    } catch (e) {
      await TokenStorage.clearToken();
      _usuario = null;
    } finally {
      _isLoading = false;
      _isInitialized = true;
      notifyListeners();
    }
  }

  Future<bool> login(String email, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await _dioClient.dio.post(
        '/auth/login',
        data: {
          'username': email.trim(),
          'password': password,
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final token = response.data['access_token'] as String;
        await TokenStorage.saveToken(token);

        // Obtener datos del usuario
        final meResponse = await _dioClient.get('/auth/me');
        if (meResponse.statusCode == 200 && meResponse.data != null) {
          _usuario = Usuario.fromJson(meResponse.data as Map<String, dynamic>);
          _isLoading = false;
          _errorMessage = null;
          notifyListeners();
          return true;
        }
      }
      _errorMessage = 'Respuesta inválida del servidor';
      _isLoading = false;
      notifyListeners();
      return false;
    } on DioException catch (e) {
      _isLoading = false;
      if (e.response != null && e.response?.data != null) {
        final data = e.response?.data;
        if (data is Map && data.containsKey('detail')) {
          _errorMessage = data['detail'].toString();
        } else {
          _errorMessage = 'Error en el servidor (${e.response?.statusCode})';
        }
      } else {
        _errorMessage = 'No se pudo conectar con el servidor: ${e.message}';
      }
      notifyListeners();
      return false;
    } catch (e) {
      _isLoading = false;
      _errorMessage = 'Ocurrió un error inesperado: $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> registro(String nombre, String email, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await _dioClient.post(
        '/auth/registro',
        data: {
          'nombre': nombre.trim(),
          'email': email.trim(),
          'password': password,
        },
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        // Iniciar sesión automáticamente tras registro
        return await login(email, password);
      } else {
        _errorMessage = 'Error al registrar usuario';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } on DioException catch (e) {
      _isLoading = false;
      if (e.response != null && e.response?.data != null) {
        final data = e.response?.data;
        if (data is Map && data.containsKey('detail')) {
          _errorMessage = data['detail'].toString();
        } else {
          _errorMessage = 'Error en el registro (${e.response?.statusCode})';
        }
      } else {
        _errorMessage = 'No se pudo conectar con el servidor: ${e.message}';
      }
      notifyListeners();
      return false;
    } catch (e) {
      _isLoading = false;
      _errorMessage = 'Ocurrió un error inesperado: $e';
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    await TokenStorage.clearToken();
    _usuario = null;
    _errorMessage = null;
    notifyListeners();
  }
}
