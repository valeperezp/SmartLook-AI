import 'package:flutter/foundation.dart';
import '../../../core/services/encargado_service.dart';

class EncargadoProvider extends ChangeNotifier {
  final EncargadoService _service = EncargadoService();

  Map<String, dynamic>? _resumen;
  List<dynamic> _inventario = [];
  List<dynamic> _movimientos = [];
  List<dynamic> _reservas = [];

  String _filtroReservas = 'todas';
  String _busquedaReservas = '';
  Map<String, dynamic>? _reservaSeleccionada;

  bool _isLoading = false;
  String? _errorMessage;

  // Getters principales
  Map<String, dynamic>? get resumen => _resumen;
  List<dynamic> get inventario => _inventario;
  List<dynamic> get movimientos => _movimientos;
  List<dynamic> get reservas => _reservas;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  // Getters para reservas
  String get filtroReservas => _filtroReservas;
  String get busquedaReservas => _busquedaReservas;
  Map<String, dynamic>? get reservaSeleccionada => _reservaSeleccionada;

  int get totalPendientes =>
      _reservas.where((r) => (r['estado']?.toString().toLowerCase() ?? '') == 'pendiente').length;

  int get totalConfirmadas =>
      _reservas.where((r) => (r['estado']?.toString().toLowerCase() ?? '') == 'confirmada').length;

  int get totalAtendidas =>
      _reservas.where((r) => (r['estado']?.toString().toLowerCase() ?? '') == 'atendida').length;

  int get totalCanceladas =>
      _reservas.where((r) => (r['estado']?.toString().toLowerCase() ?? '') == 'cancelada').length;

  /// Reservas filtradas por estado y texto de búsqueda
  List<dynamic> get reservasFiltradas {
    return _reservas.where((reserva) {
      final estado = reserva['estado']?.toString().toLowerCase() ?? '';
      final f = _filtroReservas.toLowerCase();

      // Filtro por chip de estado
      if (f != 'todas') {
        if (f == 'pendientes' && estado != 'pendiente') return false;
        if (f == 'confirmadas' && estado != 'confirmada') return false;
        if (f == 'atendidas' && estado != 'atendida') return false;
        if (f == 'canceladas' && estado != 'cancelada') return false;
      }

      // Filtro por búsqueda (nombre, email o ID de reserva)
      if (_busquedaReservas.isNotEmpty) {
        final query = _busquedaReservas.toLowerCase();
        final nombre = reserva['nombre_cliente']?.toString().toLowerCase() ?? '';
        final email = reserva['email_cliente']?.toString().toLowerCase() ?? '';
        final idStr = reserva['id']?.toString() ?? '';
        if (!nombre.contains(query) && !email.contains(query) && !idStr.contains(query)) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  void setFiltroReservas(String filtro) {
    _filtroReservas = filtro;
    notifyListeners();
  }

  void setBusquedaReservas(String query) {
    _busquedaReservas = query.trim();
    notifyListeners();
  }

  void setReservaSeleccionada(Map<String, dynamic>? reserva) {
    _reservaSeleccionada = reserva;
    notifyListeners();
  }

  /// Alertas de reposición calculadas a partir del inventario (stock bajo o agotado).
  List<dynamic> get alertas {
    return _inventario.where((item) {
      final estado = item['estado']?.toString().toLowerCase();
      final disp = item['cantidad_disponible'] as num? ?? 0;
      final min = item['stock_minimo'] as num? ?? 0;
      return estado == 'bajo' || estado == 'agotado' || disp <= min;
    }).toList();
  }

  /// Carga en paralelo los datos principales para el panel del encargado.
  Future<void> cargarDashboard() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final results = await Future.wait([
        _service.obtenerResumen(),
        _service.listarInventarioMiSucursal(),
        _service.listarMovimientos(),
        _service.listarMisReservas(),
      ]);

      _resumen = results[0] as Map<String, dynamic>;
      _inventario = results[1] as List<dynamic>;
      _movimientos = results[2] as List<dynamic>;
      _reservas = results[3] as List<dynamic>;
    } catch (e) {
      _errorMessage = 'Error al cargar datos del panel: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Carga exclusivamente el inventario de la sucursal asignada.
  Future<void> cargarInventario() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _inventario = await _service.listarInventarioMiSucursal();
    } catch (e) {
      _errorMessage = 'Error al cargar inventario: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Carga el historial de movimientos de inventario de la sucursal.
  Future<void> cargarMovimientos() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _movimientos = await _service.listarMovimientos();
    } catch (e) {
      _errorMessage = 'Error al cargar movimientos: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Carga las reservas activas asociadas a la sucursal.
  Future<void> cargarReservas() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _reservas = await _service.listarMisReservas();
    } catch (e) {
      _errorMessage = 'Error al cargar reservas: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Carga el detalle de una reserva específica.
  Future<Map<String, dynamic>?> cargarDetalleReserva(int id) async {
    try {
      final detalle = await _service.obtenerDetalleReserva(id);
      if (detalle is Map<String, dynamic>) {
        _reservaSeleccionada = detalle;
        notifyListeners();
        return detalle;
      }
      return null;
    } catch (e) {
      _errorMessage = 'Error al cargar detalle de reserva: $e';
      notifyListeners();
      return null;
    }
  }

  /// Registra una entrada o salida y recarga el dashboard.
  Future<bool> crearMovimiento(Map<String, dynamic> data) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _service.crearMovimiento(data);
      await cargarDashboard();
      return true;
    } catch (e) {
      _errorMessage = 'Error al crear movimiento: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Realiza un ajuste de existencias y recarga el dashboard.
  Future<bool> crearAjuste(Map<String, dynamic> data) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _service.crearAjuste(data);
      await cargarDashboard();
      return true;
    } catch (e) {
      _errorMessage = 'Error al realizar ajuste: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Actualiza el stock mínimo de un registro y recarga el inventario.
  Future<bool> actualizarStockMinimo(int id, int stockMinimo) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _service.actualizarStockMinimo(id, stockMinimo);
      await cargarDashboard();
      return true;
    } catch (e) {
      _errorMessage = 'Error al actualizar stock mínimo: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Cambia el estado de una reserva y recarga las reservas + dashboard.
  Future<bool> cambiarEstadoReserva(int reservaId, String nuevoEstado) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _service.cambiarEstadoReserva(reservaId, nuevoEstado);
      await cargarDashboard();
      return true;
    } catch (e) {
      _errorMessage = 'Error al cambiar estado de reserva: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Limpia los mensajes de error existentes.
  void limpiarError() {
    _errorMessage = null;
    notifyListeners();
  }
}
