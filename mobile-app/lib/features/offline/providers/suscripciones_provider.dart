import 'package:flutter/foundation.dart';

import '../../../core/database/app_database.dart';
import '../data/suscripcion_stock_dao.dart';
import '../models/catalogo_item.dart';

/// Un aviso de stock pendiente del cliente.
class SuscripcionStock {
  const SuscripcionStock({required this.id, required this.descripcion, required this.fecha, this.productoId, this.tallaId, this.colorId, this.sucursalId});

  final String id;
  final String descripcion;
  final DateTime fecha;
  final int? productoId;
  final int? tallaId;
  final int? colorId;
  final int? sucursalId;

  factory SuscripcionStock.fromMap(Map<String, dynamic> m) => SuscripcionStock(
        id: m['id'] as String,
        descripcion: m['descripcion'] as String,
        fecha: DateTime.parse(m['fecha_suscripcion'] as String).toLocal(),
        productoId: m['producto_id'] as int?,
        tallaId: m['talla_id'] as int?,
        colorId: m['color_id'] as int?,
        sucursalId: m['sucursal_id'] as int?,
      );
}

/// "Avísame cuando llegue" (CU16): suscripciones del cliente a prendas agotadas y avisos de que ya hay stock.
class SuscripcionesProvider extends ChangeNotifier {
  SuscripcionesProvider({SuscripcionStockDao? dao}) : _dao = dao ?? SuscripcionStockDao();

  final SuscripcionStockDao _dao;

  List<SuscripcionStock> _pendientes = const [];
  bool _cargando = false;
  String? _mensaje;

  List<SuscripcionStock> get pendientes => _pendientes;
  bool get cargando => _cargando;
  String? get mensaje => _mensaje;
  bool get soportado => AppDatabase.soportado;

  static String _clave(int? producto, int? talla, int? color, int? sucursal) => '$producto|${talla ?? 0}|${color ?? 0}|${sucursal ?? 0}';

  /// ¿El cliente ya espera esa prenda?
  bool estaSuscrito(CatalogoItem p) =>
      _pendientes.any((s) => _clave(s.productoId, s.tallaId, s.colorId, s.sucursalId) == _clave(p.productoId, p.tallaId, p.colorId, p.sucursalId));

  Future<void> cargar(int clienteId) async {
    if (!soportado) return;
    _cargando = true;
    notifyListeners();
    try {
      await _dao.expirarAntiguas();
      _pendientes = (await _dao.obtenerSuscripcionesPendientes(clienteId)).map(SuscripcionStock.fromMap).toList(growable: false);
    } catch (e, st) {
      debugPrint('[SuscripcionesProvider] Error al cargar las suscripciones: $e\n$st');
      _mensaje = 'No se pudieron leer tus avisos.';
    } finally {
      _cargando = false;
      notifyListeners();
    }
  }

  /// Suscribe al cliente a [p] (agotada). Devuelve si ahora queda suscrito (también si ya lo estaba).
  Future<bool> suscribirse(CatalogoItem p, int clienteId) async {
    if (p.hayStock) {
      _mensaje = 'Este producto ya tiene stock.';
      notifyListeners();
      return false;
    }
    try {
      final descripcion = p.variante.isEmpty ? p.nombre : '${p.nombre} · ${p.variante}';
      final r = await _dao.crearSuscripcion(
        clienteId: clienteId,
        productoId: p.productoId,
        tallaId: p.tallaId,
        colorId: p.colorId,
        sucursalId: p.sucursalId,
        descripcion: descripcion,
      );
      _mensaje = r.creada ? 'Te avisaremos cuando llegue "${p.nombre}".' : 'Ya estabas esperando este producto.';
      await cargar(clienteId);
      return true;
    } catch (e, st) {
      debugPrint('[SuscripcionesProvider] Error al suscribirse: $e\n$st');
      _mensaje = 'No se pudo guardar el aviso.';
      notifyListeners();
      return false;
    }
  }

  Future<void> cancelar(String id, int clienteId) async {
    try {
      await _dao.cancelar(id);
      await cargar(clienteId);
    } catch (e, st) {
      debugPrint('[SuscripcionesProvider] Error al cancelar el aviso $id: $e\n$st');
      _mensaje = 'No se pudo cancelar el aviso.';
      notifyListeners();
    }
  }

  /// Mensajes para los avisos cuyo producto ya tiene stock y que el cliente aún no vio; los marca como vistos.
  Future<List<String>> revisarAvisos(int clienteId) async {
    if (!soportado) return const [];
    try {
      final avisos = await _dao.obtenerAvisosSinVer(clienteId);
      if (avisos.isEmpty) return const [];
      await _dao.marcarVistos([for (final a in avisos) a['id'] as String]);
      await cargar(clienteId);
      return [for (final a in avisos) '¡Llegó stock de ${a['descripcion']} que esperabas!'];
    } catch (e, st) {
      debugPrint('[SuscripcionesProvider] Error al revisar los avisos: $e\n$st');
      return const [];
    }
  }
}
