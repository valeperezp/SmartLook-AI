import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:provider/provider.dart';
import '../../carrito/providers/carrito_provider.dart';
import '../providers/checkout_provider.dart';
import '../services/pagos_service.dart';

class TarjetaForm extends StatefulWidget {
  final int? ventaId;
  final double monto;
  final VoidCallback onPagoExitoso;
  final ValueChanged<String>? onError;

  const TarjetaForm({
    super.key,
    this.ventaId,
    required this.monto,
    required this.onPagoExitoso,
    this.onError,
  });

  @override
  State<TarjetaForm> createState() => _TarjetaFormState();
}

class _TarjetaFormState extends State<TarjetaForm> {
  final PagosService _pagosService = PagosService();

  // Controladores para formulario web (Modo Demo)
  final _formKey = GlobalKey<FormState>();
  final _numeroController = TextEditingController();
  final _expController = TextEditingController();
  final _cvcController = TextEditingController();
  final _titularController = TextEditingController();

  bool _procesando = false;
  String? _errorMensaje;

  @override
  void dispose() {
    _numeroController.dispose();
    _expController.dispose();
    _cvcController.dispose();
    _titularController.dispose();
    super.dispose();
  }

  void _autocompletarPrueba() {
    setState(() {
      _numeroController.text = '4242 4242 4242 4242';
      _expController.text = '12/34';
      _cvcController.text = '123';
      _titularController.text = 'CLIENTE DE PRUEBA';
      _errorMensaje = null;
    });
  }

  String? _validarNumero(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Ingresá el número de tarjeta';
    }
    final soloDigitos = value.replaceAll(RegExp(r'\s+'), '');
    if (soloDigitos.length != 16) {
      return 'El número debe tener 16 dígitos';
    }
    return null;
  }

  String? _validarExp(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Ingresá MM/AA';
    }
    final partes = value.split('/');
    if (partes.length != 2 || partes[0].length != 2 || partes[1].length != 2) {
      return 'Formato MM/AA inválido';
    }
    final mes = int.tryParse(partes[0]);
    final anio = int.tryParse(partes[1]);
    if (mes == null || mes < 1 || mes > 12) {
      return 'Mes inválido (01-12)';
    }
    if (anio == null || anio < 24) {
      return 'Año vencido';
    }
    return null;
  }

  String? _validarCvc(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Ingresá CVC';
    }
    if (value.length < 3 || value.length > 4) {
      return '3 o 4 dígitos';
    }
    return null;
  }

  /// Flujo para Flutter Web: Procesamiento en modo demostración
  Future<void> _pagarWebDemo() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _procesando = true;
      _errorMensaje = null;
    });

    final provider = context.read<CheckoutProvider>();
    final success = await provider.procesarPagoTarjeta();

    if (!mounted) return;

    setState(() {
      _procesando = false;
    });

    if (success) {
      widget.onPagoExitoso();
    } else {
      final err = provider.errorMessage ??
          'Ocurrió un error al procesar el pago con tarjeta';
      setState(() {
        _errorMensaje = err;
      });
      widget.onError?.call(err);
    }
  }

  /// Flujo Nativo para Android / iOS: Stripe PaymentSheet nativo
  Future<void> _pagarNativoStripe() async {
    setState(() {
      _procesando = true;
      _errorMensaje = null;
    });

    final checkout = context.read<CheckoutProvider>();
    final carrito = context.read<CarritoProvider>();

    int? id = widget.ventaId ?? checkout.ventaId;

    // Asegurar que la orden online exista
    if (id == null) {
      if (checkout.sucursalId == null) {
        setState(() {
          _procesando = false;
          _errorMensaje = 'Por favor selecciona una sucursal para tu pedido.';
        });
        return;
      }

      final venta = await checkout.crearOrden(
        sucursalId: checkout.sucursalId!,
        items: carrito.items,
      );

      if (venta == null) {
        setState(() {
          _procesando = false;
          _errorMensaje =
              checkout.errorMessage ?? 'No se pudo crear la orden online.';
        });
        return;
      }
      id = venta.id;
    }

    try {
      // 1. Llamar POST /pagos/crear-intent → client_secret
      final intentRes = await _pagosService.crearPaymentIntent(
        ventaId: id,
        metodo: 'tarjeta',
      );

      // 2. Inicializar Stripe PaymentSheet nativo
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: intentRes.clientSecret,
          merchantDisplayName: 'SmartLook AI',
          style: ThemeMode.system,
        ),
      );

      // 3. Presentar PaymentSheet nativo al usuario
      await Stripe.instance.presentPaymentSheet();

      // 4. Si el usuario completó el pago en Stripe, confirmar en backend
      final pagoConfirmado = await _pagosService.confirmarPago(
        paymentIntentId: intentRes.paymentIntentId,
      );

      if (!mounted) return;

      // 5. Marcar venta exitosa SOLO si el backend confirma estado "completado"
      if (pagoConfirmado.estado == 'completado') {
        checkout.marcarPagoExitosoReal(
          ordenId: id,
          pago: pagoConfirmado,
        );
        widget.onPagoExitoso();
      } else {
        setState(() {
          _errorMensaje =
              'El pago no se pudo completar. Estado actual: ${pagoConfirmado.estado}';
        });
      }
    } on StripeException catch (e) {
      debugPrint('StripeException: ${e.error.localizedMessage}');
      if (e.error.code == FailureCode.Canceled) {
        // El usuario canceló la hoja de pago voluntariamente
        setState(() {
          _errorMensaje = 'Operación de pago cancelada.';
        });
      } else {
        setState(() {
          _errorMensaje = e.error.localizedMessage ?? 'Error en la pasarela Stripe.';
        });
      }
      widget.onError?.call(_errorMensaje!);
    } catch (e) {
      debugPrint('Error en pago nativo: $e');
      setState(() {
        _errorMensaje = 'Error al procesar el pago: $e';
      });
      widget.onError?.call(_errorMensaje!);
    } finally {
      if (mounted) {
        setState(() {
          _procesando = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return _buildWebForm(context);
    } else {
      return _buildNativePaymentWidget(context);
    }
  }

  /// UI Nativa Android / iOS: Stripe PaymentSheet
  Widget _buildNativePaymentWidget(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Banner informativo Stripe Nativo
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blue.shade200),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.verified_user_outlined,
                  color: Colors.blue.shade800, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Stripe PaymentSheet Nativo',
                      style: TextStyle(
                        color: Colors.blue.shade900,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Procesamiento bancario seguro integrado con Google Pay y tarjeta con certificación PCI-DSS.',
                      style: TextStyle(
                        color: Colors.blue.shade800,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        if (_errorMensaje != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _errorMensaje!,
                    style: TextStyle(color: Colors.red.shade900, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Resumen de importe
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total a pagar:',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              Text(
                '\$${widget.monto.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Botón principal nativo
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 2,
            ),
            onPressed: _procesando ? null : _pagarNativoStripe,
            icon: _procesando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.credit_card),
            label: Text(
              _procesando
                  ? 'Abriendo pasarela...'
                  : 'Pagar \$${widget.monto.toStringAsFixed(2)} con Stripe',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        ),
      ],
    );
  }

  /// UI para Flutter Web (Modo Demo con inputs de prueba)
  Widget _buildWebForm(BuildContext context) {
    final theme = Theme.of(context);

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner de aviso
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.amber.shade300),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: Colors.amber.shade900, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Procesamiento seguro de pagos. La integración con Stripe PaymentSheet nativo está disponible en Android e iOS. En la web puedes usar este formulario para registrar la orden en modo de demostración.',
                    style: TextStyle(
                      color: Colors.amber.shade900,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          if (_errorMensaje != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline,
                      color: Colors.red.shade700, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _errorMensaje!,
                      style:
                          TextStyle(color: Colors.red.shade900, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.lock, size: 14, color: Colors.green),
                  SizedBox(width: 4),
                  Text(
                    'Pago encriptado TLS',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
              TextButton.icon(
                onPressed: _autocompletarPrueba,
                icon: const Icon(Icons.flash_on, size: 16),
                label: const Text('Tarjeta de prueba',
                    style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Número de tarjeta
          TextFormField(
            controller: _numeroController,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(16),
              _CardNumberInputFormatter(),
            ],
            decoration: InputDecoration(
              labelText: 'Número de tarjeta',
              hintText: '4242 4242 4242 4242',
              prefixIcon: const Icon(Icons.credit_card),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
            validator: _validarNumero,
          ),
          const SizedBox(height: 14),

          // Vencimiento + CVC
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextFormField(
                  controller: _expController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                    _CardExpiryInputFormatter(),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Vencimiento',
                    hintText: 'MM/AA',
                    prefixIcon: const Icon(Icons.calendar_today_outlined),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                  ),
                  validator: _validarExp,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: _cvcController,
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                  ],
                  decoration: InputDecoration(
                    labelText: 'CVC / CVV',
                    hintText: '123',
                    prefixIcon: const Icon(Icons.lock_outline),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                  ),
                  validator: _validarCvc,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Nombre del titular
          TextFormField(
            controller: _titularController,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: 'Nombre del titular',
              hintText: 'COMO FIGURA EN LA TARJETA',
              prefixIcon: const Icon(Icons.person_outline),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Ingresá el nombre del titular';
              }
              return null;
            },
          ),
          const SizedBox(height: 20),

          // Botón Pagar Web
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _procesando ? null : _pagarWebDemo,
              icon: _procesando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.payment),
              label: Text(
                _procesando
                    ? 'Procesando pago...'
                    : 'Pagar \$${widget.monto.toStringAsFixed(2)}',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CardNumberInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text.replaceAll(' ', '');
    final buffer = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      buffer.write(text[i]);
      final nonZeroIndex = i + 1;
      if (nonZeroIndex % 4 == 0 && nonZeroIndex != text.length) {
        buffer.write(' ');
      }
    }
    final string = buffer.toString();
    return newValue.copyWith(
      text: string,
      selection: TextSelection.collapsed(offset: string.length),
    );
  }
}

class _CardExpiryInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final cleaned = newValue.text.replaceAll('/', '');
    final newText = cleaned.length > 2
        ? '${cleaned.substring(0, 2)}/${cleaned.substring(2)}'
        : cleaned;
    return newValue.copyWith(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );
  }
}
