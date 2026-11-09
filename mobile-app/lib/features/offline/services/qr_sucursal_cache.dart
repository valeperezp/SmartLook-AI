import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/config/env.dart';
import '../../../core/network/dio_client.dart';
import '../../encargado/mi_qr/models/sucursal_qr.dart';
import '../../encargado/mi_qr/services/sucursal_qr_service.dart';
import '../data/qr_sucursal_cache_dao.dart';

typedef ConsultarQrSucursal = Future<SucursalQR?> Function(int sucursalId);
typedef DescargarImagen = Future<List<int>> Function(String url);

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
  Future<int> actualizar(Iterable<int> sucursalIds) async {
    var guardadas = 0;
    for (final id in sucursalIds.toSet()) {
      try {
        final qr = await _consultar(id);
        if (qr == null || !qr.activo || qr.imagenUrl.isEmpty) {
          await _dao.eliminar(id); // la sucursal ya no tiene QR activo: no se queda uno viejo
          continue;
        }
        final bytes = await _descargar(_resolverUrl(qr.imagenUrl));
        await _dao.guardar(id, bytes, url: qr.imagenUrl);
        guardadas++;
      } catch (e) {
        debugPrint('[QrSucursalCache] No se pudo guardar el QR de la sucursal $id: $e'); // se queda con el que tenía
      }
    }
    return guardadas;
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
