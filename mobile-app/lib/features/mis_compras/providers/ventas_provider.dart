import 'package:flutter/foundation.dart';
import '../../../core/models/venta.dart';
import '../services/ventas_service.dart';

class VentasProvider extends ChangeNotifier {
  final VentasService _service = VentasService();

  List<Venta> _compras = [];
  bool _isLoading = false;
  String? _errorMessage;
  Venta? _ventaSeleccionada;

  List<Venta> get compras => List.unmodifiable(_compras);
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  Venta? get ventaSeleccionada => _ventaSeleccionada;

  Future<void> cargarCompras() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _compras = await _service.listarMisCompras();
    } catch (e) {
      _errorMessage = 'Error al cargar compras: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Venta?> cargarDetalle(int id) async {
    try {
      final venta = await _service.obtenerVenta(id);
      _ventaSeleccionada = venta;
      notifyListeners();
      return venta;
    } catch (e) {
      debugPrint('Error al obtener detalle de venta: $e');
      return null;
    }
  }

  void limpiarSeleccion() {
    _ventaSeleccionada = null;
    notifyListeners();
  }
}
