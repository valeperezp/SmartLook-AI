import 'package:flutter/foundation.dart';
import '../models/promocion.dart';
import '../services/promociones_service.dart';

class PromocionesProvider with ChangeNotifier {
  final PromocionesService _service = PromocionesService();

  List<Promocion> _promociones = [];
  bool _isLoading = false;
  bool _isSaving = false;
  String? _errorMessage;
  bool _soloActivas = false;

  // Getters
  List<Promocion> get promociones => _promociones;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get errorMessage => _errorMessage;
  bool get soloActivas => _soloActivas;

  /// Carga la lista de promociones desde el backend.
  Future<void> cargarPromociones({bool? soloActivas}) async {
    if (soloActivas != null) {
      _soloActivas = soloActivas;
    }
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _promociones = await _service.listar(soloActivas: _soloActivas);
      _isLoading = false;
      _errorMessage = null;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
    }
  }

  /// Cambia el filtro de solo activas / todas.
  Future<void> cambiarFiltroActivas(bool soloActivas) async {
    _soloActivas = soloActivas;
    await cargarPromociones();
  }

  /// Crea una nueva promoción.
  Future<bool> crearPromocion(Map<String, dynamic> datos) async {
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final nueva = await _service.crear(datos);
      _promociones.insert(0, nueva);
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

  /// Actualiza una promoción existente.
  Future<bool> actualizarPromocion(int id, Map<String, dynamic> datos) async {
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final actualizada = await _service.actualizar(id, datos);
      final index = _promociones.indexWhere((p) => p.id == id);
      if (index != -1) {
        _promociones[index] = actualizada;
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

  /// Desactiva una promoción.
  Future<bool> desactivarPromocion(int id) async {
    try {
      final desc = await _service.desactivar(id);
      final index = _promociones.indexWhere((p) => p.id == id);
      if (index != -1) {
        _promociones[index] = desc;
      }
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  /// Reactiva una promoción desactivada.
  Future<bool> reactivarPromocion(int id) async {
    try {
      final react = await _service.reactivar(id);
      final index = _promociones.indexWhere((p) => p.id == id);
      if (index != -1) {
        _promociones[index] = react;
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
