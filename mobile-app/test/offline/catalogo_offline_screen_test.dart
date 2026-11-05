import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smartlook_mobile/features/auth/providers/auth_provider.dart';
import 'package:smartlook_mobile/features/offline/models/catalogo_item.dart';
import 'package:smartlook_mobile/features/offline/providers/catalogo_offline_provider.dart';
import 'package:smartlook_mobile/features/offline/providers/conectividad_provider.dart';
import 'package:smartlook_mobile/features/offline/providers/suscripciones_provider.dart';
import 'package:smartlook_mobile/features/offline/screens/catalogo_offline_screen.dart';
import 'package:smartlook_mobile/features/offline/services/sync_service.dart';

class _CatalogoFalso extends CatalogoOfflineProvider {
  _CatalogoFalso(this._items);

  final List<CatalogoItem> _items;

  @override
  List<CatalogoItem> get productos => _items;

  @override
  bool get soportado => false;

  @override
  Future<void> cargar() async {}
}

class _SuscripcionesFalso extends SuscripcionesProvider {
  @override
  bool get soportado => false;

  @override
  Future<void> cargar(int clienteId) async {}
}

class _SyncFalso implements SyncService {
  @override
  Stream<ResultadoSync> get alSincronizarAutomaticamente => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _AuthFalso extends ChangeNotifier implements AuthProvider {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

CatalogoItem _item(int id, {required int stock}) => CatalogoItem(
      inventarioId: id,
      sucursalId: 1,
      productoId: id,
      nombre: 'Prenda $id',
      precioCentavos: 10000,
      cantidadDisponible: stock,
      activo: true,
    );

void main() {
  testWidgets('la cuadrícula del catálogo offline se dibuja sin errores (con y sin stock)', (tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<CatalogoOfflineProvider>(create: (_) => _CatalogoFalso([_item(1, stock: 5), _item(2, stock: 0), _item(3, stock: 2)])),
          ChangeNotifierProvider<SuscripcionesProvider>(create: (_) => _SuscripcionesFalso()),
          ChangeNotifierProvider<AuthProvider>(create: (_) => _AuthFalso()),
          ChangeNotifierProvider<ConectividadProvider>(create: (_) => ConectividadProvider(cambios: const Stream.empty(), consultar: () async => [])),
          Provider<SyncService>(create: (_) => _SyncFalso()),
        ],
        child: const MaterialApp(home: CatalogoOfflineScreen()),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Prenda 1'), findsOneWidget);
    expect(find.text('Avísame cuando llegue'), findsOneWidget);
  });
}
