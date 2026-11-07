import '../config/regla_devoluciones.dart';
import '../network/dio_client.dart';

/// Pide el JSON de [ruta] al backend (se puede reemplazar en pruebas).
typedef ObtenerJsonDevoluciones = Future<Map<String, dynamic>> Function(String ruta);

/// Cambios y devoluciones (CU11) contra el backend. Solo descarga la regla del plazo: las devoluciones en sí viajan por la
/// cola de sincronización y es el backend quien las aprueba o las rechaza.
class DevolucionesService {
  DevolucionesService({ObtenerJsonDevoluciones? obtener}) : _obtener = obtener ?? _porDio;

  final ObtenerJsonDevoluciones _obtener;

  static Future<Map<String, dynamic>> _porDio(String ruta) async {
    final r = await DioClient().get<Map<String, dynamic>>(ruta);
    return r.data ?? const {};
  }

  /// Descarga el plazo (en días) que el backend admite para cambios y devoluciones (`GET /devoluciones/configuracion`)
  /// y lo guarda para usarlo como estimación sin conexión.
  Future<int> sincronizarPlazo() async {
    final json = await _obtener('/devoluciones/configuracion');
    final dias = json['plazo_dias'] as int? ?? ReglaDevoluciones.plazoDias;
    await ReglaDevoluciones.guardar(dias);
    return dias;
  }
}
