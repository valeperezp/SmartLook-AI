import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:provider/provider.dart';
import 'core/config/env.dart';
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
import 'features/proveedor/providers/proveedor_provider.dart';
import 'features/reservas/providers/reservas_provider.dart';
import 'features/vestidor/providers/vestidor_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    Stripe.publishableKey = Env.stripePublishableKey;
    await Stripe.instance.applySettings();
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

  @override
  void initState() {
    super.initState();
    _authProvider = AuthProvider();
    _appRouter = AppRouter(_authProvider);
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
      ],
      child: MaterialApp.router(
        title: 'SmartLook AI',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        themeMode: ThemeMode.light,
        routerConfig: _appRouter.router,
      ),
    );
  }
}
