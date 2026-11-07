import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:provider/provider.dart';
import 'core/config/env.dart';
import 'core/config/regla_devoluciones.dart';
import 'core/config/regla_puntos.dart';
import 'core/network/dio_client.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/admin/providers/admin_provider.dart';
import 'features/admin/reportes/providers/reportes_provider.dart';
import 'features/admin/promociones/providers/promociones_provider.dart';
import 'features/admin/ia_config/providers/ia_config_provider.dart';
import 'features/admin/sucursales/providers/sucursales_admin_provider.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/carrito/providers/carrito_provider.dart';
import 'features/catalogo/providers/catalogo_provider.dart';
import 'features/checkout/providers/checkout_provider.dart';
import 'features/encargado/providers/encargado_provider.dart';
import 'features/encargado/ventas/providers/ventas_sucursal_provider.dart';
import 'features/encargado/pagos_pendientes/providers/pagos_pendientes_provider.dart';
import 'features/encargado/mi_qr/providers/sucursal_qr_provider.dart';
import 'features/encargado/movimientos/providers/movimientos_provider.dart';
import 'features/cajero/pos/providers/pos_provider.dart';
import 'features/cajero/ventas/providers/mis_ventas_provider.dart';
import 'features/cajero/qr/providers/qr_cajero_provider.dart';
import 'features/ia/providers/ia_provider.dart';
import 'features/mis_compras/providers/ventas_provider.dart';
import 'features/offline/providers/catalogo_offline_provider.dart';
import 'features/offline/providers/conectividad_provider.dart';
import 'features/offline/providers/devolucion_provider.dart';
import 'features/offline/providers/puntos_provider.dart';
import 'features/offline/providers/suscripciones_provider.dart';
import 'features/offline/providers/turno_caja_provider.dart';
import 'features/offline/providers/venta_offline_provider.dart';
import 'features/offline/services/sync_service.dart';
import 'features/proveedor/providers/proveedor_provider.dart';
import 'features/reservas/providers/reservas_provider.dart';
import 'features/vestidor/providers/vestidor_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ReglaPuntos.cargarGuardada(); // la regla de puntos de la empresa (viene del backend), para usarla sin conexión
  await ReglaDevoluciones.cargarGuardada(); // el plazo de cambios y devoluciones que informó el backend (solo estimación local)
  if (!kIsWeb) {
    try {
      Stripe.publishableKey = Env.stripePublishableKey;
      await Stripe.instance.applySettings();
    } catch (e) {
      debugPrint('Error al inicializar Stripe: $e');
    }
  }
  runApp(const SmartLookApp());
}

typedef MyApp = SmartLookApp;

class SmartLookApp extends StatefulWidget {
  const SmartLookApp({super.key});

  @override
  State<SmartLookApp> createState() => _SmartLookAppState();
}

class _SmartLookAppState extends State<SmartLookApp> {
  late final AuthProvider _authProvider;
  late final AppRouter _appRouter;
  bool _reseteoEn401Instalado = false;

  @override
  void initState() {
    super.initState();
    _authProvider = AuthProvider();
    _appRouter = AppRouter(_authProvider);
  }

  /// Ante un 401 con sesion activa, vacia los datos personales/transitorios de vestidor y checkout.
  /// El carrito no se toca. Se encadena sobre el callback que AuthProvider registro en DioClient.
  void _instalarReseteoEn401(BuildContext context) {
    if (_reseteoEn401Instalado) return;
    _reseteoEn401Instalado = true;
    final dio = DioClient();
    final alNoAutorizado = dio.onUnauthorized;
    dio.onUnauthorized = () {
      if (_authProvider.isLoggedIn && context.mounted) {
        context.read<VestidorProvider>().limpiarFoto();
        context.read<CheckoutProvider>().reset();
      }
      alNoAutorizado?.call();
    };
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: _authProvider),
        ChangeNotifierProvider<CatalogoProvider>(
          create: (_) => CatalogoProvider(),
        ),
        ChangeNotifierProvider<ReservasProvider>(
          create: (_) => ReservasProvider(),
        ),
        ChangeNotifierProvider<CarritoProvider>(
          create: (_) => CarritoProvider(),
        ),
        ChangeNotifierProvider<CheckoutProvider>(
          create: (_) => CheckoutProvider(),
        ),
        ChangeNotifierProvider<VentasProvider>(
          create: (_) => VentasProvider(),
        ),
        ChangeNotifierProvider<IaProvider>(
          create: (_) => IaProvider(),
        ),
        ChangeNotifierProvider<VestidorProvider>(
          create: (_) => VestidorProvider(),
        ),
        ChangeNotifierProvider<AdminProvider>(
          create: (_) => AdminProvider(),
        ),
        ChangeNotifierProvider<ReportesProvider>(
          create: (_) => ReportesProvider(),
        ),
        ChangeNotifierProvider<PromocionesProvider>(
          create: (_) => PromocionesProvider(),
        ),
        ChangeNotifierProvider<IaConfigProvider>(
          create: (_) => IaConfigProvider(),
        ),
        ChangeNotifierProvider<SucursalesAdminProvider>(
          create: (_) => SucursalesAdminProvider(),
        ),
        ChangeNotifierProvider<EncargadoProvider>(
          create: (_) => EncargadoProvider(),
        ),
        ChangeNotifierProvider<VentasSucursalProvider>(
          create: (_) => VentasSucursalProvider(),
        ),
        ChangeNotifierProvider<PagosPendientesProvider>(
          create: (_) => PagosPendientesProvider(),
        ),
        ChangeNotifierProvider<SucursalQrProvider>(
          create: (_) => SucursalQrProvider(),
        ),
        ChangeNotifierProvider<MovimientosProvider>(
          create: (_) => MovimientosProvider(),
        ),
        ChangeNotifierProvider<PosProvider>(
          create: (_) => PosProvider(),
        ),
        ChangeNotifierProvider<MisVentasProvider>(
          create: (_) => MisVentasProvider(),
        ),
        ChangeNotifierProvider<QrCajeroProvider>(
          create: (_) => QrCajeroProvider(),
        ),
        ChangeNotifierProvider<ProveedorProvider>(
          create: (_) => ProveedorProvider(),
        ),
        ChangeNotifierProvider<CatalogoOfflineProvider>(
          create: (_) => CatalogoOfflineProvider(),
        ),
        ChangeNotifierProvider<VentaOfflineProvider>(
          create: (_) => VentaOfflineProvider(),
        ),
        // Sincroniza con POST /sync/operaciones; si el endpoint aún no existe (404) la cola queda pendiente
        // lazy: false → empieza a escuchar la red desde el arranque; dispose cancela la suscripción
        Provider<SyncService>(
          lazy: false,
          create: (_) => SyncService()..iniciarEscucha(),
          dispose: (_, sync) => sync.dispose(),
        ),
        ChangeNotifierProvider<ConectividadProvider>(
          create: (_) => ConectividadProvider(),
        ),
        ChangeNotifierProvider<TurnoCajaProvider>(
          create: (_) => TurnoCajaProvider(),
        ),
        ChangeNotifierProvider<DevolucionProvider>(
          create: (_) => DevolucionProvider(),
        ),
        ChangeNotifierProvider<PuntosProvider>(
          create: (_) => PuntosProvider(),
        ),
        ChangeNotifierProvider<SuscripcionesProvider>(
          create: (_) => SuscripcionesProvider(),
        ),
      ],
      child: MaterialApp.router(
        title: 'SmartLook AI',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        themeMode: ThemeMode.light,
        routerConfig: _appRouter.router,
        builder: (context, child) {
          _instalarReseteoEn401(context);
          return child ?? const SizedBox.shrink();
        },
      ),
    );
  }
}
