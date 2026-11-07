import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smartlook_mobile/core/database/app_database.dart';
import 'package:smartlook_mobile/core/database/schema.dart';
import 'package:smartlook_mobile/features/auth/providers/auth_provider.dart';
import 'package:smartlook_mobile/features/offline/data/catalogo_local_dao.dart';
import 'package:smartlook_mobile/features/offline/data/sync_queue_dao.dart';
import 'package:smartlook_mobile/features/offline/models/catalogo_item.dart';
import 'package:smartlook_mobile/features/offline/providers/catalogo_offline_provider.dart';
import 'package:smartlook_mobile/features/offline/providers/conectividad_provider.dart';
import 'package:smartlook_mobile/features/offline/providers/suscripciones_provider.dart';
import 'package:smartlook_mobile/features/offline/screens/catalogo_offline_screen.dart';
import 'package:smartlook_mobile/features/offline/services/sync_service.dart';
import 'package:smartlook_mobile/features/offline/widgets/banner_catalogo_desactualizado.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _textoAviso = 'La información puede estar desactualizada. Conéctate a internet para actualizar.';

/// CU8 — aviso "Información desactualizada" si el catálogo guardado tiene más de 24 horas.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('regla de las 24 horas', () {
    final ahora = DateTime.utc(2026, 11, 7, 12);

    test('sin catálogo (fecha nula) no hay aviso', () {
      expect(CatalogoOfflineProvider.estaDesactualizado(null, ahora), isFalse);
    });

    test('menos de 24 h o justo 24 h: no; pasadas las 24 h: sí', () {
      expect(CatalogoOfflineProvider.estaDesactualizado(ahora.subtract(const Duration(hours: 23, minutes: 59)), ahora), isFalse);
      expect(CatalogoOfflineProvider.estaDesactualizado(ahora.subtract(const Duration(hours: 24)), ahora), isFalse);
      expect(CatalogoOfflineProvider.estaDesactualizado(ahora.subtract(const Duration(hours: 24, minutes: 1)), ahora), isTrue);
      expect(CatalogoOfflineProvider.estaDesactualizado(ahora.subtract(const Duration(days: 2)), ahora), isTrue);
    });

    test('una fecha futura (reloj desajustado) no genera aviso', () {
      expect(CatalogoOfflineProvider.estaDesactualizado(ahora.add(const Duration(hours: 5)), ahora), isFalse);
    });

    test('el texto de antigüedad cuenta en horas hasta 48 h y en días después', () {
      expect(BannerCatalogoDesactualizado.antiguedadTexto(const Duration(minutes: 10)), 'hace 1 hora');
      expect(BannerCatalogoDesactualizado.antiguedadTexto(const Duration(hours: 30)), 'hace 30 horas');
      expect(BannerCatalogoDesactualizado.antiguedadTexto(const Duration(days: 2, hours: 3)), 'hace 2 días');
    });
  });

  group('CatalogoOfflineProvider con la base local', () {
    late AppDatabase appDb;
    late CatalogoOfflineProvider provider;

    setUp(() async {
      appDb = AppDatabase.conBaseDeDatos(await AppDatabase.abrir(inMemoryDatabasePath));
      provider = CatalogoOfflineProvider(
        catalogoDao: CatalogoLocalDao(appDatabase: appDb),
        colaDao: SyncQueueDao(appDatabase: appDb),
      );
    });

    tearDown(() => appDb.cerrar());

    /// Simula un catálogo descargado hace [hace] (la descarga real guarda `sincronizado_en` = ahora).
    Future<void> envejecerCatalogo(Duration hace) async {
      final fecha = DateTime.now().toUtc().subtract(hace).toIso8601String();
      await (await appDb.database)!.rawUpdate('UPDATE ${Schema.tablaCatalogoLocal} SET sincronizado_en = ?', [fecha]);
    }

    test('sin catálogo guardado no hay fecha ni aviso', () async {
      await provider.cargar();

      expect(provider.descargadoEn, isNull);
      expect(provider.desactualizado, isFalse);
    });

    test('un catálogo recién descargado no está desactualizado y guarda la fecha exacta de la descarga', () async {
      final antes = DateTime.now().toUtc().subtract(const Duration(seconds: 1));
      await provider.cargarDatosMock();

      expect(provider.descargadoEn, isNotNull);
      expect(provider.descargadoEn!.isAfter(antes), isTrue);
      expect(provider.desactualizado, isFalse);
    });

    test('un catálogo de hace 2 días SÍ está desactualizado', () async {
      await provider.cargarDatosMock();
      await envejecerCatalogo(const Duration(days: 2));

      await provider.cargar();

      expect(provider.desactualizado, isTrue);
      expect(provider.antiguedad!.inHours, inInclusiveRange(47, 49));
    });

    test('uno de hace 23 horas todavía no', () async {
      await provider.cargarDatosMock();
      await envejecerCatalogo(const Duration(hours: 23));

      await provider.cargar();

      expect(provider.desactualizado, isFalse);
    });

    test('al volver a descargar el catálogo el aviso desaparece', () async {
      await provider.cargarDatosMock();
      await envejecerCatalogo(const Duration(days: 3));
      await provider.cargar();
      expect(provider.desactualizado, isTrue);

      await provider.cargarDatosMock(); // nueva descarga: todas las filas con la fecha de ahora

      expect(provider.desactualizado, isFalse);
    });

    test('con un reloj inyectado, la misma descarga pasa a desactualizada al día siguiente', () async {
      var reloj = DateTime.now();
      final conReloj = CatalogoOfflineProvider(
        catalogoDao: CatalogoLocalDao(appDatabase: appDb),
        colaDao: SyncQueueDao(appDatabase: appDb),
        ahora: () => reloj,
      );
      await conReloj.cargarDatosMock();
      expect(conReloj.desactualizado, isFalse);

      reloj = reloj.add(const Duration(hours: 25));

      expect(conReloj.desactualizado, isTrue);
    });
  });

  group('pantalla del catálogo offline', () {
    Future<void> montar(WidgetTester tester, CatalogoOfflineProvider provider) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<CatalogoOfflineProvider>.value(value: provider),
            ChangeNotifierProvider<SuscripcionesProvider>(create: (_) => _SuscripcionesFalso()),
            ChangeNotifierProvider<AuthProvider>(create: (_) => _AuthFalso()),
            ChangeNotifierProvider<ConectividadProvider>(create: (_) => ConectividadProvider(cambios: const Stream.empty(), consultar: () async => [])),
            Provider<SyncService>(create: (_) => _SyncFalso()),
          ],
          child: const MaterialApp(home: CatalogoOfflineScreen()),
        ),
      );
      await tester.pump();
    }

    testWidgets('con el catálogo de hace 2 días muestra el banner de información desactualizada sobre la lista', (tester) async {
      await montar(tester, _CatalogoFalso([_item(1)], hace: const Duration(days: 2)));

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('banner_catalogo_desactualizado')), findsOneWidget);
      expect(find.text('Información desactualizada'), findsOneWidget);
      expect(find.text(_textoAviso), findsOneWidget);
      expect(find.text('Última actualización: hace 2 días.'), findsOneWidget);
      // el banner va arriba de la lista de productos
      expect(
        tester.getTopLeft(find.byKey(const Key('banner_catalogo_desactualizado'))).dy,
        lessThan(tester.getTopLeft(find.text('Prenda 1')).dy),
      );
    });

    testWidgets('con un catálogo reciente NO muestra el banner', (tester) async {
      await montar(tester, _CatalogoFalso([_item(1)], hace: const Duration(hours: 2)));

      expect(find.byKey(const Key('banner_catalogo_desactualizado')), findsNothing);
      expect(find.text(_textoAviso), findsNothing);
      expect(find.text('Prenda 1'), findsOneWidget);
    });
  });
}

class _CatalogoFalso extends CatalogoOfflineProvider {
  _CatalogoFalso(this._items, {required this.hace});

  final List<CatalogoItem> _items;
  final Duration hace;

  @override
  List<CatalogoItem> get productos => _items;

  @override
  DateTime? get descargadoEn => DateTime.now().subtract(hace);

  @override
  Duration? get antiguedad => hace;

  @override
  bool get desactualizado => hace > limiteCatalogoDesactualizado;

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

CatalogoItem _item(int id) => CatalogoItem(
      inventarioId: id,
      sucursalId: 1,
      productoId: id,
      nombre: 'Prenda $id',
      precioCentavos: 10000,
      cantidadDisponible: 3,
      activo: true,
    );
