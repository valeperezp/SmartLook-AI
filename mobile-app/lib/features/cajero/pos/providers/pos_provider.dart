import 'package:flutter/foundation.dart';
import '../../../../core/models/categoria.dart';
import '../../../../core/models/disponibilidad.dart';
import '../../../../core/models/producto.dart';
import '../../../../core/models/venta.dart';
import '../models/item_carrito_pos.dart';
import '../services/pos_service.dart';

class PosProvider with ChangeNotifier {
  final PosService _service = PosService();

  final List<ItemCarritoPos> _carrito = [];
  List<Producto> _productos = [];
  List<Categoria> _categorias = [];

  bool _isLoadingProductos = false;
  bool _isProcesandoVenta = false;
  String? _errorMessage;

  String _busqueda = '';
  int? _categoriaSeleccionada;
  int? _sucursalId;

  Venta? _ultimaVenta;

  // Getters
  List<ItemCarritoPos> get carrito => List.unmodifiable(_carrito);
  List<Producto> get productos => _productos;
  List<Categoria> get categorias => _categorias;

  bool get isLoadingProductos => _isLoadingProductos;
  bool get isProcesandoVenta => _isProcesandoVenta;
  String? get errorMessage => _errorMessage;

  String get busqueda => _busqueda;
  int? get categoriaSeleccionada => _categoriaSeleccionada;
  Venta? get ultimaVenta => _ultimaVenta;

  double get total => _carrito.fold(0.0, (acc, item) => acc + item.subtotal);
  int get unidades => _carrito.fold(0, (acc, item) => acc + item.cantidad);

  List<Producto> get productosFiltrados {
    final q = _busqueda.toLowerCase().trim();
    return _productos.where((p) {
      final matchCat = _categoriaSeleccionada == null || p.categoriaId == _categoriaSeleccionada;
      final matchQ = q.isEmpty ||
          p.nombre.toLowerCase().contains(q) ||
          (p.descripcion?.toLowerCase().contains(q) ?? false) ||
          p.categoriaNombre.toLowerCase().contains(q);
      return matchCat && matchQ;
    }).toList();
  }

  /// Carga inicial del catálogo de productos y categorías para el POS.
  Future<void> cargarCatalogo({int? sucursalId}) async {
    _sucursalId = sucursalId;
    _isLoadingProductos = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final results = await Future.wait([
        _service.buscarProductos(sucursalId: sucursalId),
        _service.listarCategorias(),
      ]);

      _productos = results[0] as List<Producto>;
      _categorias = results[1] as List<Categoria>;
      _isLoadingProductos = false;
      notifyListeners();
    } catch (e) {
      _isLoadingProductos = false;
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
    }
  }

  void setBusqueda(String q) {
    _busqueda = q;
    notifyListeners();
  }

  void setCategoria(int? catId) {
    _categoriaSeleccionada = catId;
    notifyListeners();
  }

  /// Agrega un ítem al carrito POS. Si ya existe la misma prenda, talla y color, suma la cantidad.
  void agregarAlCarrito(
    Producto producto, {
    DisponibilidadTallaColor? variante,
    int cantidad = 1,
  }) {
    final tallaId = variante?.tallaId;
    final colorId = variante?.colorId;
    final maxStock = variante != null ? variante.cantidadDisponible : producto.totalDisponible;

    final existingIndex = _carrito.indexWhere(
      (item) =>
          item.productoId == producto.id &&
          item.tallaId == tallaId &&
          item.colorId == colorId,
    );

    if (existingIndex > -1) {
      final actual = _carrito[existingIndex];
      final nuevaCant = actual.cantidad + cantidad;
      if (nuevaCant <= maxStock) {
        actual.cantidad = nuevaCant;
      } else {
        actual.cantidad = maxStock;
      }
    } else {
      _carrito.add(ItemCarritoPos(
        productoId: producto.id,
        nombreProducto: producto.nombre,
        precio: producto.precio,
        tallaId: tallaId,
        nombreTalla: variante?.nombreTalla,
        colorId: colorId,
        nombreColor: variante?.nombreColor,
        cantidad: cantidad <= maxStock ? cantidad : maxStock,
        stockMaximo: maxStock,
      ));
    }
    notifyListeners();
  }

  /// Modifica la cantidad de un ítem existente en el carrito.
  void actualizarCantidad(int index, int delta) {
    if (index < 0 || index >= _carrito.length) return;
    final item = _carrito[index];
    final nuevaCant = item.cantidad + delta;

    if (nuevaCant <= 0) {
      _carrito.removeAt(index);
    } else if (nuevaCant <= item.stockMaximo) {
      item.cantidad = nuevaCant;
    }
    notifyListeners();
  }

  /// Elimina un ítem del carrito.
  void eliminarItem(int index) {
    if (index >= 0 && index < _carrito.length) {
      _carrito.removeAt(index);
      notifyListeners();
    }
  }

  /// Vacía todo el carrito del POS.
  void vaciarCarrito() {
    _carrito.clear();
    notifyListeners();
  }

  /// Obtiene la disponibilidad detallada de un producto en la sucursal actual.
  Future<ProductoDisponibilidad> consultarDisponibilidad(int productoId) {
    return _service.consultarStock(productoId);
  }

  /// Registra la venta presencial en el backend y limpia el carrito.
  Future<Venta?> registrarVenta({
    required int sucursalId,
    int? clienteId,
  }) async {
    if (_carrito.isEmpty) {
      _errorMessage = 'El carrito está vacío';
      notifyListeners();
      return null;
    }

    _isProcesandoVenta = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final itemsPayload = _carrito.map((item) => item.toVentaItemJson()).toList();
      final venta = await _service.crearVentaPresencial(
        sucursalId: sucursalId,
        clienteId: clienteId,
        items: itemsPayload,
      );

      _ultimaVenta = venta;
      _carrito.clear();
      _isProcesandoVenta = false;
      notifyListeners();

      // Recargar catálogo para actualizar existencias de stock
      cargarCatalogo(sucursalId: _sucursalId);

      return venta;
    } catch (e) {
      _isProcesandoVenta = false;
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return null;
    }
  }

  void limpiarError() {
    _errorMessage = null;
    notifyListeners();
  }
}
