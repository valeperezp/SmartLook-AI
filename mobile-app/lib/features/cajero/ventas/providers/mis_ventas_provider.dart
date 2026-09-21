import 'package:flutter/foundation.dart';
import '../../../../core/models/venta.dart';
import '../../../checkout/models/pago.dart';
import '../services/mis_ventas_service.dart';

class MisVentasProvider with ChangeNotifier {
  final MisVentasService _service = MisVentasService();

  List<Venta> _ventas = [];
  bool _isLoading = false;
  String? _errorMessage;

  String _filtroFecha = 'hoy'; // 'hoy' | 'semana' | 'mes' | 'todas'
  String _filtroEstado = 'todas'; // 'todas' | 'completada' | 'pendiente' | 'cancelada'
  String _busqueda = '';

  Venta? _ventaSeleccionada;
  List<Pago> _pagosVenta = [];
  bool _cargandoPagos = false;

  // Getters
  List<Venta> get ventas => _ventas;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  String get filtroFecha => _filtroFecha;
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
      final fecha = v.creadaEn.toLocal();

      // Filtro por fecha
      if (_filtroFecha == 'hoy' && fecha.isBefore(hoyInicio)) return false;
      if (_filtroFecha == 'semana' && fecha.isBefore(semanaInicio)) return false;
      if (_filtroFecha == 'mes' && fecha.isBefore(mesInicio)) return false;

      // Filtro por estado
      if (_filtroEstado != 'todas' && v.estado.toLowerCase() != _filtroEstado.toLowerCase()) {
        return false;
      }

      // Filtro por término de búsqueda
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

  // KPIs
  int get totalVentas => ventasFiltradas.length;

  double get totalFacturado =>
      ventasFiltradas.fold(0.0, (acc, v) => acc + v.total);

  double get ticketPromedio =>
      totalVentas > 0 ? (totalFacturado / totalVentas) : 0.0;

  int get totalUnidades =>
      ventasFiltradas.fold(0, (acc, v) => acc + v.totalUnidades);

  /// Carga las ventas de la sucursal del cajero.
  Future<void> cargarVentas(int sucursalId, {int? cajeroId}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final list = await _service.listarVentasSucursal(sucursalId);
      // Si se pasa cajeroId, se priorizan o filtran sus ventas si están asociadas
      if (cajeroId != null) {
        final misVentas = list.where((v) => v.cajeroId == cajeroId).toList();
        _ventas = misVentas.isNotEmpty ? misVentas : list;
      } else {
        _ventas = list;
      }
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
    }
  }

  void setFiltroFecha(String filtro) {
    _filtroFecha = filtro;
    notifyListeners();
  }

  void setFiltroEstado(String filtro) {
    _filtroEstado = filtro;
    notifyListeners();
  }

  void setBusqueda(String q) {
    _busqueda = q;
    notifyListeners();
  }

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

  void limpiarSeleccion() {
    _ventaSeleccionada = null;
    _pagosVenta = [];
    _cargandoPagos = false;
    notifyListeners();
  }
}
