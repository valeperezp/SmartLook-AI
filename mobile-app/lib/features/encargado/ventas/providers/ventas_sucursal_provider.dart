import 'package:flutter/foundation.dart';
import '../../../../core/models/venta.dart';
import '../../../checkout/models/pago.dart';
import '../services/ventas_sucursal_service.dart';

class VentasSucursalProvider with ChangeNotifier {
  final VentasSucursalService _service = VentasSucursalService();

  List<Venta> _ventas = [];
  bool _isLoading = false;
  String? _errorMessage;

  // Filtros
  String _filtroFecha = 'hoy'; // 'hoy' | 'semana' | 'mes' | 'todas'
  String _filtroCanal = 'todos'; // 'todos' | 'presencial' | 'online'
  String _filtroEstado = 'todos'; // 'todos' | 'completada' | 'pendiente' | 'cancelada'
  String _busqueda = '';

  // Detalle de venta seleccionada
  Venta? _ventaSeleccionada;
  List<Pago> _pagosVenta = [];
  bool _cargandoPagos = false;

  // Getters
  List<Venta> get ventas => _ventas;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  String get filtroFecha => _filtroFecha;
  String get filtroCanal => _filtroCanal;
  String get filtroEstado => _filtroEstado;
  String get busqueda => _busqueda;

  Venta? get ventaSeleccionada => _ventaSeleccionada;
  List<Pago> get pagosVenta => _pagosVenta;
  bool get cargandoPagos => _cargandoPagos;

  List<Venta> get ventasFiltradas {
    final ahora = DateTime.now();
    final hoyInicio = DateTime(ahora.year, ahora.month, ahora.day);
    final semanaInicio = ahora.subtract(const Duration(days: 7));
    final mesInicio = DateTime(ahora.year, ahora.month, 1);

    final q = _busqueda.toLowerCase().trim();

    return _ventas.where((v) {
      final fechaLocal = v.creadaEn.toLocal();

      // Filtro por fecha
      if (_filtroFecha == 'hoy' && fechaLocal.isBefore(hoyInicio)) return false;
      if (_filtroFecha == 'semana' && fechaLocal.isBefore(semanaInicio)) return false;
      if (_filtroFecha == 'mes' && fechaLocal.isBefore(mesInicio)) return false;

      // Filtro por canal
      if (_filtroCanal != 'todos' && v.canal.toLowerCase() != _filtroCanal.toLowerCase()) {
        return false;
      }

      // Filtro por estado
      if (_filtroEstado != 'todos' && v.estado.toLowerCase() != _filtroEstado.toLowerCase()) {
        return false;
      }

      // Búsqueda por ID, cliente o cajero
      if (q.isNotEmpty) {
        final matchId = v.id.toString().contains(q);
        final matchCliente = v.nombreCliente?.toLowerCase().contains(q) ?? false;
        final matchCajero = v.nombreCajero?.toLowerCase().contains(q) ?? false;
        if (!matchId && !matchCliente && !matchCajero) return false;
      }

      return true;
    }).toList()
      ..sort((a, b) => b.creadaEn.compareTo(a.creadaEn));
  }

  // KPIs calculados sobre la lista filtrada
  int get totalVentas => ventasFiltradas.length;

  double get montoTotal =>
      ventasFiltradas.fold(0.0, (acc, v) => acc + v.total);

  double get ticketPromedio =>
      totalVentas > 0 ? (montoTotal / totalVentas) : 0.0;

  int get unidadesVendidas =>
      ventasFiltradas.fold(0, (acc, v) => acc + v.totalUnidades);

  // Carga principal
  Future<void> cargarVentas(int sucursalId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _ventas = await _service.listarVentas(sucursalId);
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
    }
  }

  // Setters de filtros
  void setFiltroFecha(String filtro) {
    if (_filtroFecha != filtro) {
      _filtroFecha = filtro;
      notifyListeners();
    }
  }

  void setFiltroCanal(String filtro) {
    if (_filtroCanal != filtro) {
      _filtroCanal = filtro;
      notifyListeners();
    }
  }

  void setFiltroEstado(String filtro) {
    if (_filtroEstado != filtro) {
      _filtroEstado = filtro;
      notifyListeners();
    }
  }

  void setBusqueda(String query) {
    _busqueda = query;
    notifyListeners();
  }

  // Selección de venta y carga de sus pagos
  Future<void> seleccionarVenta(Venta venta) async {
    _ventaSeleccionada = venta;
    _pagosVenta = [];
    _cargandoPagos = true;
    notifyListeners();

    try {
      _pagosVenta = await _service.listarPagosVenta(venta.id);
    } catch (_) {
      _pagosVenta = [];
    } finally {
      _cargandoPagos = false;
      notifyListeners();
    }
  }

  void limpiarVentaSeleccionada() {
    _ventaSeleccionada = null;
    _pagosVenta = [];
    _cargandoPagos = false;
    notifyListeners();
  }
}
