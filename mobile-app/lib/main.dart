import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/admin/providers/admin_provider.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/catalogo/providers/catalogo_provider.dart';
import 'features/encargado/providers/encargado_provider.dart';
import 'features/proveedor/providers/proveedor_provider.dart';
import 'features/reservas/providers/reservas_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
        ChangeNotifierProvider<AdminProvider>(
          create: (_) => AdminProvider(),
        ),
        ChangeNotifierProvider<EncargadoProvider>(
          create: (_) => EncargadoProvider(),
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
