import '../config/regla_puntos.dart';
import '../network/dio_client.dart';

/// Saldo de puntos de un cliente y la regla de su empresa, tal como los devuelve el backend.
class PuntosServidor {
  const PuntosServidor({required this.clienteId, required this.saldo, required this.valorPuntoCentavos});

  final int clienteId;
  final int saldo;

  /// Cuánto descuenta cada punto (regla de la empresa).
  final int valorPuntoCentavos;

  factory PuntosServidor.fromJson(Map<String, dynamic> json) => PuntosServidor(
        clienteId: json['cliente_id'] as int? ?? 0,
        saldo: json['saldo'] as int? ?? 0,
        valorPuntoCentavos: json['valor_punto_centavos'] as int? ?? ReglaPuntos.valorPorDefectoCentavos,
      );
}

/// Pide el JSON de [ruta] al backend (se puede reemplazar en pruebas).
typedef ObtenerJson = Future<Map<String, dynamic>> Function(String ruta);

/// Puntos de fidelización (CU17) contra el backend. Cada respuesta actualiza la [ReglaPuntos] guardada en el
/// dispositivo: así la regla "cuánto vale un punto" siempre sale del backend y funciona después sin conexión.
class FidelizacionService {
  FidelizacionService({ObtenerJson? obtener}) : _obtener = obtener ?? _porDio;

  final ObtenerJson _obtener;

  static Future<Map<String, dynamic>> _porDio(String ruta) async {
    final r = await DioClient().get<Map<String, dynamic>>(ruta);
    return r.data ?? const {};
  }

  /// Saldo del cliente con sesión iniciada (`GET /clientes/mis-puntos`).
  Future<PuntosServidor> misPuntos() => _leerPuntos('/clientes/mis-puntos');

  /// Saldo de un cliente de la misma empresa (`GET /clientes/{id}/puntos`): lo consulta el cajero al cobrar.
  Future<PuntosServidor> puntosDeCliente(int clienteId) => _leerPuntos('/clientes/$clienteId/puntos');

  /// El personal de venta descarga la regla de su empresa (`GET /clientes/regla-puntos`) para usarla offline.
  Future<int> sincronizarRegla() async {
    final json = await _obtener('/clientes/regla-puntos');
    final valor = json['valor_punto_centavos'] as int? ?? ReglaPuntos.valorPuntoCentavos;
    await ReglaPuntos.guardar(valor);
    return valor;
  }

  Future<PuntosServidor> _leerPuntos(String ruta) async {
    final puntos = PuntosServidor.fromJson(await _obtener(ruta));
    await ReglaPuntos.guardar(puntos.valorPuntoCentavos);
    return puntos;
  }
}
