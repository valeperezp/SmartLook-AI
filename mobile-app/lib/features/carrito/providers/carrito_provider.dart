import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/carrito_item.dart';

class CarritoProvider extends ChangeNotifier {
  static const String _storageKey = 'smartlook_cart';

  List<CarritoItem> _items = [];
  bool _isInitialized = false;

  List<CarritoItem> get items => List.unmodifiable(_items);
  bool get isInitialized => _isInitialized;

  double get total =>
      _items.fold(0.0, (acc, item) => acc + (item.precio * item.cantidad));

  int get cantidadTotal =>
      _items.fold(0, (acc, item) => acc + item.cantidad);

  bool get estaVacio => _items.isEmpty;

  CarritoProvider() {
    _cargarDeStorage();
  }

  Future<void> _cargarDeStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          _items = decoded
              .map((item) =>
                  CarritoItem.fromJson(item as Map<String, dynamic>))
              .toList();
        }
      }
    } catch (e) {
      debugPrint('Error al cargar carrito desde SharedPreferences: $e');
      _items = [];
    } finally {
      _isInitialized = true;
      notifyListeners();
    }
  }

  Future<void> _guardarEnStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(_items.map((i) => i.toJson()).toList());
      await prefs.setString(_storageKey, encoded);
    } catch (e) {
      debugPrint('Error al guardar carrito en SharedPreferences: $e');
    }
  }

  void agregar(CarritoItem nuevo) {
    if (nuevo.cantidad <= 0) return;

    final index = _items.findIndex(
      (it) =>
          it.productoId == nuevo.productoId &&
          it.tallaId == nuevo.tallaId &&
          it.colorId == nuevo.colorId,
    );

    if (index > -1) {
      final actual = _items[index];
      var nuevaCantidad = actual.cantidad + nuevo.cantidad;
      if (actual.maxDisponible != null && nuevaCantidad > actual.maxDisponible!) {
        nuevaCantidad = actual.maxDisponible!;
      }
      _items[index] = actual.copyWith(cantidad: nuevaCantidad);
    } else {
      var cantidadFinal = nuevo.cantidad;
      if (nuevo.maxDisponible != null && cantidadFinal > nuevo.maxDisponible!) {
        cantidadFinal = nuevo.maxDisponible!;
      }
      _items.add(nuevo.copyWith(cantidad: cantidadFinal));
    }

    _guardarEnStorage();
    notifyListeners();
  }

  void actualizarCantidad(int index, int cantidad) {
    if (index < 0 || index >= _items.length) return;

    if (cantidad <= 0) {
      eliminar(index);
      return;
    }

    final item = _items[index];
    var cantFinal = cantidad;
    if (item.maxDisponible != null && cantFinal > item.maxDisponible!) {
      cantFinal = item.maxDisponible!;
    }

    _items[index] = item.copyWith(cantidad: cantFinal);
    _guardarEnStorage();
    notifyListeners();
  }

  void eliminar(int index) {
    if (index < 0 || index >= _items.length) return;
    _items.removeAt(index);
    _guardarEnStorage();
    notifyListeners();
  }

  void vaciar() {
    _items.clear();
    _guardarEnStorage();
    notifyListeners();
  }
}

extension _IterableExtension<T> on List<T> {
  int findIndex(bool Function(T element) test) {
    for (var i = 0; i < length; i++) {
      if (test(this[i])) return i;
    }
    return -1;
  }
}
