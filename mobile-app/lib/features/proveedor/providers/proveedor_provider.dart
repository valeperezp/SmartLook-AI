import 'package:flutter/foundation.dart';
import '../../../core/services/proveedor_service.dart';

class ProveedorProvider extends ChangeNotifier {
  final ProveedorService _service = ProveedorService();

  List<dynamic> _misProductos = [];
  List<dynamic> _categorias = [];
  List<dynamic> _temporadas = [];
  List<dynamic> _colecciones = [];
  List<dynamic> _tallas = [];
  List<dynamic> _colores = [];

  bool _isLoading = false;
  String? _errorMessage;

  String _busqueda = '';
  String _filtroEstado = 'todos'; // 'todos' | 'activos' | 'inactivos'

  // Getters
  List<dynamic> get misProductos => _misProductos;
  List<dynamic> get categorias => _categorias;
  List<dynamic> get temporadas => _temporadas;
  List<dynamic> get colecciones => _colecciones;
  List<dynamic> get tallas => _tallas;
  List<dynamic> get colores => _colores;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  String get busqueda => _busqueda;
  String get filtroEstado => _filtroEstado;

  int get totalProductos => _misProductos.length;
  int get totalActivos => _misProductos.where((p) => p['activo'] == true).length;
  int get totalInactivos => _misProductos.where((p) => p['activo'] == false).length;

  /// Total de categorías distintas cubiertas por los productos del proveedor.
  int get totalCategorias {
    final ids = _misProductos
        .map((p) => p['categoria_id'] ?? p['categoria']?['id'])
        .where((id) => id != null)
        .toSet();
    return ids.isNotEmpty ? ids.length : _categorias.length;
  }

  /// Lista filtrada por texto de búsqueda (nombre o categoría) y estado activo/inactivo.
  List<dynamic> get productosFiltrados {
    return _misProductos.where((prod) {
      final activo = prod['activo'] == true;
      final f = _filtroEstado.toLowerCase();

      if (f == 'activos' && !activo) return false;
      if (f == 'inactivos' && activo) return false;

      if (_busqueda.isNotEmpty) {
        final query = _busqueda.toLowerCase();
        final nombre = prod['nombre']?.toString().toLowerCase() ?? '';
        final catNombre = prod['categoria']?['nombre']?.toString().toLowerCase() ?? '';
        if (!nombre.contains(query) && !catNombre.contains(query)) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  /// Carga en paralelo productos, categorías, temporadas y colecciones para el dashboard.
  Future<void> cargarDashboard() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final results = await Future.wait([
        _service.listarMisProductos(incluirInactivos: true),
        _service.listarCategorias(),
        _service.listarTemporadas(),
        _service.listarColecciones(),
        _service.listarTallas(),
        _service.listarColores(),
      ]);

      _misProductos = results[0];
      _categorias = results[1];
      _temporadas = results[2];
      _colecciones = results[3];
      _tallas = results[4];
      _colores = results[5];
    } catch (e) {
      _errorMessage = 'Error al cargar datos del proveedor: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Carga exclusivamente los productos del proveedor.
  Future<void> cargarMisProductos() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _misProductos = await _service.listarMisProductos(incluirInactivos: true);
    } catch (e) {
      _errorMessage = 'Error al cargar productos: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Crea un nuevo producto y recarga los datos del proveedor.
  Future<bool> crearProducto(Map<String, dynamic> data) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _service.crearProducto(data);
      await cargarDashboard();
      return true;
    } catch (e) {
      _errorMessage = 'Error al crear producto: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Actualiza un producto existente y recarga los datos del proveedor.
  Future<bool> actualizarProducto(int id, Map<String, dynamic> data) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _service.actualizarProducto(id, data);
      await cargarDashboard();
      return true;
    } catch (e) {
      _errorMessage = 'Error al actualizar producto: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Desactiva (soft-delete) un producto y recarga los datos.
  Future<bool> desactivarProducto(int id) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _service.desactivarProducto(id);
      await cargarDashboard();
      return true;
    } catch (e) {
      _errorMessage = 'Error al desactivar producto: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Reactiva un producto desactivado.
  Future<bool> reactivarProducto(int id) async {
    return await actualizarProducto(id, {'activo': true});
  }

  void setBusqueda(String query) {
    _busqueda = query.trim();
    notifyListeners();
  }

  void setFiltroEstado(String filtro) {
    _filtroEstado = filtro;
    notifyListeners();
  }

  void limpiarError() {
    _errorMessage = null;
    notifyListeners();
  }
}
