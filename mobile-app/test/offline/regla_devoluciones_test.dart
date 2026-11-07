import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartlook_mobile/core/config/regla_devoluciones.dart';
import 'package:smartlook_mobile/core/services/devoluciones_service.dart';
import 'package:smartlook_mobile/features/offline/data/devolucion_dao.dart';
import 'package:smartlook_mobile/features/offline/models/devolucion_models.dart';

/// CU11 — el plazo de cambios y devoluciones lo manda el backend; el móvil solo lo usa como estimación.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ReglaDevoluciones.restablecer();
  });
  tearDown(ReglaDevoluciones.restablecer);

  test('por defecto 7 días hasta recibir el plazo de la empresa', () {
    expect(ReglaDevoluciones.plazoDias, 7);
  });

  test('el plazo que informa el backend se guarda y se recupera al arrancar (para estimar sin conexión)', () async {
    await ReglaDevoluciones.guardar(15);
    ReglaDevoluciones.restablecer();
    expect(ReglaDevoluciones.plazoDias, 7);

    await ReglaDevoluciones.cargarGuardada();

    expect(ReglaDevoluciones.plazoDias, 15);
  });

  test('valores inválidos del servidor se ignoran', () async {
    await ReglaDevoluciones.guardar(0);
    ReglaDevoluciones.establecer(-3);

    expect(ReglaDevoluciones.plazoDias, 7);
  });

  test('sincronizarPlazo descarga el plazo de GET /devoluciones/configuracion', () async {
    String? ruta;
    final servicio = DevolucionesService(obtener: (r) async {
      ruta = r;
      return {'plazo_dias': 30};
    });

    expect(await servicio.sincronizarPlazo(), 30);

    expect(ruta, '/devoluciones/configuracion');
    expect(ReglaDevoluciones.plazoDias, 30);
  });

  test('si el backend no responde, el plazo estimado no cambia', () async {
    final servicio = DevolucionesService(obtener: (_) async => throw Exception('sin red'));

    await expectLater(servicio.sincronizarPlazo(), throwsException);

    expect(ReglaDevoluciones.plazoDias, 7);
  });

  test('el DAO y la estimación de la venta usan el plazo del backend (no un 7 fijo)', () {
    expect(DevolucionDao().plazoDias, 7);

    ReglaDevoluciones.establecer(3);

    expect(DevolucionDao().plazoDias, 3);
    expect(DevolucionDao(plazoDias: 20).plazoDias, 20, reason: 'un valor explícito (pruebas) manda sobre el guardado');
    final venta = VentaLocal(uuid: 'abcdef12-xxxx', fecha: DateTime.now().subtract(const Duration(days: 4)), totalCentavos: 1000, estado: 'sincronizada');
    expect(venta.dentroDePlazo(DevolucionDao().plazoDias), isFalse);
    expect(venta.dentroDePlazo(10), isTrue);
  });
}
