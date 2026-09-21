import 'package:flutter/foundation.dart';
import '../../../../core/models/sucursal.dart';
import '../services/sucursales_admin_service.dart';

class SucursalesAdminProvider with ChangeNotifier {
  final SucursalesAdminService _service = SucursalesAdminService();

  List<Sucursal> _sucursales = [];
  bool _isLoading = false;
  bool _isSaving = false;
  String? _errorMessage;

  // Getters
  List<Sucursal> get sucursales => _sucursales;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get errorMessage => _errorMessage;

  /// Carga la lista completa de sucursales desde el backend.
  Future<void> cargarSucursales() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _sucursales = await _service.listar();
      _isLoading = false;
      _errorMessage = null;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
    }
  }

  /// Crea una nueva sucursal.
  Future<bool> crearSucursal(Map<String, dynamic> datos) async {
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final nueva = await _service.crear(datos);
      _sucursales.add(nueva);
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

  /// Actualiza una sucursal existente.
  Future<bool> actualizarSucursal(int id, Map<String, dynamic> datos) async {
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final actualizada = await _service.actualizar(id, datos);
      final index = _sucursales.indexWhere((s) => s.id == id);
      if (index != -1) {
        _sucursales[index] = actualizada;
      }
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

  /// Desactiva/elimina una sucursal.
  Future<bool> desactivarSucursal(int id) async {
    try {
      final desc = await _service.desactivar(id);
      final index = _sucursales.indexWhere((s) => s.id == id);
      if (index != -1) {
        _sucursales[index] = desc;
      }
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return false;
    }
  }
}
