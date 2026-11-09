import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/config/env.dart';
import '../../../core/network/dio_client.dart';
import '../../encargado/mi_qr/models/sucursal_qr.dart';
import '../../encargado/mi_qr/services/sucursal_qr_service.dart';
import '../data/qr_sucursal_cache_dao.dart';

typedef ConsultarQrSucursal = Future<SucursalQR?> Function(int sucursalId);
typedef DescargarImagen = Future<List<int>> Function(String url);

/// Qué pasó con el QR de cada sucursal en una actualización.
class ResultadoQrCache {
  const ResultadoQrCache({this.guardadas = const [], this.sinQr = const [], this.fallidas = const {}});

  /// Sucursales cuyo QR quedó guardado en el celular.
  final List<int> guardadas;

  /// Sucursales que no tienen un QR activo configurado (no es un error de la app: falta que el encargado lo suba).
  final List<int> sinQr;

  /// Sucursales cuyo QR NO se pudo guardar, con el motivo (la imagen no está en el servidor, sin conexión...).
  final Map<int, String> fallidas;

  /// Por qué NO hay QR guardado de [sucursalId] (null si se guardó o no se intentó).
  String? motivoDe(int sucursalId) => fallidas[sucursalId] ?? (sinQr.contains(sucursalId) ? 'La sucursal no tiene un QR configurado.' : null);
}

/// Mantiene en el celular una copia del QR bancario de cada sucursal para poder cobrar compras offline.
///
/// Se actualiza mientras hay red (al descargar el catálogo): por cada sucursal pide su QR activo y guarda la imagen. Cada sucursal
/// es independiente (un fallo no detiene a las demás) y nunca lanza: sin red simplemente se queda con lo que ya había.
class QrSucursalCache {
  QrSucursalCache({QrSucursalCacheDao? dao, ConsultarQrSucursal? consultar, DescargarImagen? descargar})
      : _dao = dao ?? QrSucursalCacheDao(),
        _consultar = consultar ?? ((id) => SucursalQrService().obtenerQR(id)),
        _descargar = descargar ?? _descargarPorHttp;

  final QrSucursalCacheDao _dao;
  final ConsultarQrSucursal _consultar;
  final DescargarImagen _descargar;

  /// Descarga y guarda el QR de cada sucursal de [sucursalIds]. Devuelve cuántas quedaron guardadas.
  Future<int> actualizar(Iterable<int> sucursalIds) async => (await actualizarConDetalle(sucursalIds)).guardadas.length;

  /// Igual que [actualizar] pero dice qué pasó con cada sucursal: así un fallo (p. ej. la imagen del QR ya no está en el servidor)
  /// no queda oculto y se le puede explicar al usuario. Nunca lanza.
  Future<ResultadoQrCache> actualizarConDetalle(Iterable<int> sucursalIds) async {
    final guardadas = <int>[];
    final sinQr = <int>[];
    final fallidas = <int, String>{};
    for (final id in sucursalIds.toSet()) {
      try {
        final qr = await _consultar(id);
        if (qr == null || !qr.activo || qr.imagenUrl.isEmpty) {
          await _dao.eliminar(id); // la sucursal ya no tiene QR activo: no se queda uno viejo
          sinQr.add(id);
          continue;
        }
        final bytes = await _descargar(_resolverUrl(qr.imagenUrl));
        if (bytes.isEmpty) throw StateError('la imagen del QR llegó vacía');
        await _dao.guardar(id, bytes, url: qr.imagenUrl);
        guardadas.add(id);
      } catch (e) {
        final motivo = _motivoDe(e);
        debugPrint('[QrSucursalCache] No se pudo guardar el QR de la sucursal $id: $motivo ($e)'); // se queda con el que tenía
        fallidas[id] = motivo;
      }
    }
    return ResultadoQrCache(guardadas: guardadas, sinQr: sinQr, fallidas: fallidas);
  }

  /// El motivo de un fallo, en palabras que se le puedan decir al usuario.
  static String _motivoDe(Object e) {
    if (e is DioException) {
      final codigo = e.response?.statusCode;
      if (codigo == 404) return 'la imagen del QR no está en el servidor (error 404): el encargado debe volver a subirla';
      if (codigo != null) return 'el servidor respondió con el error $codigo';
      return 'sin conexión con el servidor';
    }
    return e is StateError ? e.message : 'error inesperado ($e)';
  }

  /// La imagen guardada del QR de [sucursalId] (null si no hay).
  Future<Uint8List?> obtener(int sucursalId) => _dao.obtener(sucursalId);

  static String _resolverUrl(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    return url.startsWith('/') ? '${Env.apiUrl}$url' : '${Env.apiUrl}/$url';
  }

  static Future<List<int>> _descargarPorHttp(String url) async {
    final r = await DioClient().dio.get<List<int>>(url, options: Options(responseType: ResponseType.bytes));
    return r.data ?? const <int>[];
  }
}
