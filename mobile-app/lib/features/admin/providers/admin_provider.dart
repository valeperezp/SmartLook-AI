import 'package:flutter/foundation.dart';
import '../../../core/services/admin_service.dart';

class AdminProvider extends ChangeNotifier {
  final AdminService _service = AdminService();

  Map<String, dynamic>? _resumen;
  List<dynamic> _usuarios = [];
  List<dynamic> _productos = [];
  List<dynamic> _sucursales = [];
  List<dynamic> _alertas = [];
  List<dynamic> _inventario = [];
  String _filtroInventario = 'todos';

  bool _isLoading = false;
  String? _errorMessage;

  Map<String, dynamic>? get resumen => _resumen;
  List<dynamic> get usuarios => _usuarios;
  List<dynamic> get productos => _productos;
  List<dynamic> get sucursales => _sucursales;
  List<dynamic> get alertas => _alertas;
  List<dynamic> get inventario => _inventario;
  String get filtroInventario => _filtroInventario;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  List<dynamic> get inventarioFiltrado {
    final f = _filtroInventario.toLowerCase();
    if (f == 'disponibles') {
      return _inventario.where((i) => i['estado'] == 'disponible').toList();
    }
    if (f == 'stock bajo') {
      return _inventario.where((i) => i['estado'] == 'bajo').toList();
    }
    if (f == 'agotados') {
      return _inventario.where((i) => i['estado'] == 'agotado').toList();
    }
    return _inventario;
  }

  void setFiltroInventario(String filtro) {
    _filtroInventario = filtro;
    notifyListeners();
  }

  Future<void> cargarDashboard() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final results = await Future.wait([
        _service.obtenerResumenInventario(),
        _service.listarInventarioAlertas(),
      ]);
      _resumen = results[0] as Map<String, dynamic>;
      _alertas = results[1] as List<dynamic>;
    } catch (e) {
      _errorMessage = 'Error al cargar dashboard de administrador: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> cargarUsuarios() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _usuarios = await _service.listarUsuarios();
    } catch (e) {
      _errorMessage = 'Error al cargar usuarios: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> cargarProductos() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _productos = await _service.listarProductos();
    } catch (e) {
      _errorMessage = 'Error al cargar productos: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> cargarSucursales() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _sucursales = await _service.listarSucursales();
    } catch (e) {
      _errorMessage = 'Error al cargar sucursales: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> cargarTodo() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final results = await Future.wait([
        _service.obtenerResumenInventario(),
        _service.listarInventarioAlertas(),
        _service.listarUsuarios(),
        _service.listarProductos(),
        _service.listarSucursales(),
      ]);

      _resumen = results[0] as Map<String, dynamic>;
      _alertas = results[1] as List<dynamic>;
      _usuarios = results[2] as List<dynamic>;
      _productos = results[3] as List<dynamic>;
      _sucursales = results[4] as List<dynamic>;
    } catch (e) {
      _errorMessage = 'Error al cargar datos de administración: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> cargarInventario() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _inventario = await _service.listarInventarioGlobal();
    } catch (e) {
      _errorMessage = 'Error al cargar inventario: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
