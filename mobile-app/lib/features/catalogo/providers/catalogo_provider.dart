import 'package:flutter/foundation.dart';
import '../../../core/models/categoria.dart';
import '../../../core/models/producto.dart';
import '../../../core/models/sucursal.dart';
import '../../../core/services/catalogo_service.dart';

class CatalogoProvider extends ChangeNotifier {
  final CatalogoService _service = CatalogoService();

  List<Producto> _productos = [];
  List<Producto> _productosFiltrados = [];
  List<Categoria> _categorias = [];
  List<Sucursal> _sucursales = [];

  bool _isLoading = false;
  String? _errorMessage;
  int? _categoriaSeleccionada;
  int? _sucursalSeleccionada;
  String _busqueda = '';

  List<Producto> get productos => _productos;
  List<Producto> get productosFiltrados => _productosFiltrados;
  List<Categoria> get categorias => _categorias;
  List<Sucursal> get sucursales => _sucursales;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  int? get categoriaSeleccionada => _categoriaSeleccionada;
  int? get sucursalSeleccionada => _sucursalSeleccionada;
  String get busqueda => _busqueda;

  CatalogoProvider() {
    cargarDatosIniciales();
  }

  Future<void> cargarDatosIniciales() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final results = await Future.wait([
        _service.listarCategorias(),
        _service.listarSucursales(),
        _service.listarProductos(
          categoriaId: _categoriaSeleccionada,
          sucursalId: _sucursalSeleccionada,
        ),
      ]);

      _categorias = results[0] as List<Categoria>;
      _sucursales = results[1] as List<Sucursal>;
      _productos = results[2] as List<Producto>;
      aplicarFiltrosLocalmente();
    } catch (e) {
      _errorMessage = 'Error al cargar catálogo: $e';
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
      _productos = await _service.listarProductos(
        categoriaId: _categoriaSeleccionada,
        sucursalId: _sucursalSeleccionada,
      );
      aplicarFiltrosLocalmente();
    } catch (e) {
      _errorMessage = 'Error al cargar productos: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void setCategoria(int? id) {
    if (_categoriaSeleccionada == id) return;
    _categoriaSeleccionada = id;
    cargarProductos();
  }

  void setSucursal(int? id) {
    if (_sucursalSeleccionada == id) return;
    _sucursalSeleccionada = id;
    cargarProductos();
  }

  void setBusqueda(String query) {
    _busqueda = query;
    aplicarFiltrosLocalmente();
    notifyListeners();
  }

  void aplicarFiltrosLocalmente() {
    final query = _busqueda.trim().toLowerCase();
    if (query.isEmpty) {
      _productosFiltrados = List.from(_productos);
    } else {
      _productosFiltrados = _productos.where((p) {
        final matchNombre = p.nombre.toLowerCase().contains(query);
        final matchDesc = p.descripcion?.toLowerCase().contains(query) ?? false;
        final matchCat = p.categoriaNombre.toLowerCase().contains(query);
        return matchNombre || matchDesc || matchCat;
      }).toList();
    }
  }

  void limpiarFiltros() {
    _categoriaSeleccionada = null;
    _sucursalSeleccionada = null;
    _busqueda = '';
    cargarProductos();
  }
}
