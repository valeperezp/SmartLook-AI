import 'package:flutter/foundation.dart';
import '../models/movimiento_inventario.dart';
import '../services/movimientos_service.dart';

class MovimientosProvider with ChangeNotifier {
  final MovimientosService _service = MovimientosService();

  List<MovimientoInventario> _movimientos = [];
  bool _isLoading = false;
  String? _errorMessage;

  String _filtroTipo = 'todos'; // 'todos' | 'entrada' | 'salida' | 'ajuste' | 'venta'
  String _busqueda = '';
  DateTime? _fechaInicio;
  DateTime? _fechaFin;
  int? _sucursalId;

  // Getters
  List<MovimientoInventario> get movimientos => _movimientos;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String get filtroTipo => _filtroTipo;
  String get busqueda => _busqueda;
  DateTime? get fechaInicio => _fechaInicio;
  DateTime? get fechaFin => _fechaFin;
  int? get sucursalId => _sucursalId;

  /// Lista filtrada según tipo, texto y rango de fechas.
  List<MovimientoInventario> get movimientosFiltrados {
    return _movimientos.where((m) {
      // Filtro por tipo
      if (_filtroTipo != 'todos' && m.tipo.toLowerCase() != _filtroTipo.toLowerCase()) {
        return false;
      }

      // Filtro por texto
      if (_busqueda.isNotEmpty) {
        final query = _busqueda.toLowerCase();
        final prod = m.nombreProducto?.toLowerCase() ?? '';
        final motivo = m.motivo?.toLowerCase() ?? '';
        final usuario = m.nombreUsuario?.toLowerCase() ?? '';
        final idStr = m.id.toString();
        if (!prod.contains(query) &&
            !motivo.contains(query) &&
            !usuario.contains(query) &&
            !idStr.contains(query)) {
          return false;
        }
      }

      // Filtro por fecha inicio
      if (_fechaInicio != null) {
        final inicioDia = DateTime(_fechaInicio!.year, _fechaInicio!.month, _fechaInicio!.day);
        if (m.creadoEn.isBefore(inicioDia)) return false;
      }

      // Filtro por fecha fin
      if (_fechaFin != null) {
        final finDia = DateTime(_fechaFin!.year, _fechaFin!.month, _fechaFin!.day, 23, 59, 59);
        if (m.creadoEn.isAfter(finDia)) return false;
      }

      return true;
    }).toList();
  }

  /// Carga la lista de movimientos desde el backend.
  Future<void> cargarMovimientos({int? sucursalId}) async {
    if (sucursalId != null) {
      _sucursalId = sucursalId;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _movimientos = await _service.listarMovimientos(
        sucursalId: _sucursalId,
        limit: 200,
      );
      _isLoading = false;
      _errorMessage = null;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
    }
  }

  void setFiltroTipo(String tipo) {
    _filtroTipo = tipo;
    notifyListeners();
  }

  void setBusqueda(String query) {
    _busqueda = query.trim();
    notifyListeners();
  }

  void setRangoFechas(DateTime? inicio, DateTime? fin) {
    _fechaInicio = inicio;
    _fechaFin = fin;
    notifyListeners();
  }

  void limpiarFiltros() {
    _filtroTipo = 'todos';
    _busqueda = '';
    _fechaInicio = null;
    _fechaFin = null;
    notifyListeners();
  }
}
