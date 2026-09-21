import 'package:flutter/foundation.dart';
import '../models/producto_ar.dart';
import '../services/vestidor_service.dart';

class VestidorProvider extends ChangeNotifier {
  final VestidorService _service = VestidorService();

  ProductoAr? _productoActual;
  List<ProductoAr> _productos = [];
  bool _cargando = false;
  String? _errorMessage;
  int _modoVisor = 0; // 0: 3D Model / Silueta, 1: Vestidor Web

  ProductoAr? get productoActual => _productoActual;
  List<ProductoAr> get productos => _productos;
  bool get cargando => _cargando;
  String? get errorMessage => _errorMessage;
  int get modoVisor => _modoVisor;

  void setModoVisor(int modo) {
    _modoVisor = modo;
    notifyListeners();
  }

  void seleccionarProducto(ProductoAr prod) {
    _productoActual = prod;
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> cargarProductosCatalogo({int? seleccionarId}) async {
    _cargando = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final list = await _service.listarProductos();
      _productos = list;

      if (seleccionarId != null) {
        final match = list.where((p) => p.productoId == seleccionarId);
        if (match.isNotEmpty) {
          _productoActual = match.first;
        } else {
          // Si no está en el listado general, consultar el detalle individual
          await cargarProducto(seleccionarId);
        }
      } else if (_productoActual == null && list.isNotEmpty) {
        // Seleccionar preferentemente el primero que tenga modelo AR, o el primero de la lista
        final conAr = list.where((p) => p.tieneAr);
        _productoActual = conAr.isNotEmpty ? conAr.first : list.first;
      }
    } catch (e) {
      _errorMessage = 'Error al cargar productos para el vestidor: $e';
    } finally {
      _cargando = false;
      notifyListeners();
    }
  }

  Future<void> cargarProducto(int id) async {
    _cargando = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final prod = await _service.obtenerProductoAR(id);
      _productoActual = prod;
      // Si no estaba en la lista, agregarlo
      if (!_productos.any((p) => p.productoId == prod.productoId)) {
        _productos.insert(0, prod);
      }
    } catch (e) {
      _errorMessage = 'No se pudo obtener el detalle del producto para el vestidor';
    } finally {
      _cargando = false;
      notifyListeners();
    }
  }

  void seleccionarPorId(int id) {
    final match = _productos.where((p) => p.productoId == id);
    if (match.isNotEmpty) {
      _productoActual = match.first;
      notifyListeners();
    } else {
      cargarProducto(id);
    }
  }
}
