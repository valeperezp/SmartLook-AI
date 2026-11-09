import 'package:flutter/material.dart';

import '../../../core/models/reserva.dart';
import '../../offline/data/qr_devolucion_dao.dart';

/// Qué aviso de reembolso corresponde a un pedido cancelado.
enum TipoBannerReembolso {
  /// Rojo: todavía no adjuntó su QR bancario. Tocarlo abre la cámara / galería.
  adjuntar,

  /// Rojo: el servidor rechazó el QR que había enviado; tiene que adjuntar otro.
  rechazado,

  /// Naranja: el QR está guardado en el celular y se enviará cuando haya conexión.
  enCola,

  /// Verde: el servidor ya tiene su QR; solo falta que le transfieran.
  recibido,
}

/// Aviso que corresponde a un pedido (reserva o compra) según si admite reembolso, si el servidor ya tiene su QR ([tieneQr]) y el
/// estado local del QR ([local]). Null si no hay nada que avisar.
TipoBannerReembolso? tipoBannerReembolsoDe({required bool admiteReembolso, required bool tieneQr, required QrLocal local}) {
  if (!admiteReembolso) return null;
  if (local.estado == EstadoQrLocal.enCola) return TipoBannerReembolso.enCola;
  if (tieneQr) return TipoBannerReembolso.recibido;
  if (local.estado == EstadoQrLocal.rechazado) return TipoBannerReembolso.rechazado;
  return TipoBannerReembolso.adjuntar;
}

/// Aviso que corresponde a [reserva] según el estado local de su QR ([local]), o null si no hay nada que avisar (el pedido no
/// está cancelado, o ya fue reembolsado).
TipoBannerReembolso? tipoBannerReembolso(Reserva reserva, QrLocal local) =>
    // solo `cancelada` / `reembolso_pendiente`: `reembolsada` ya no tiene nada pendiente
    tipoBannerReembolsoDe(admiteReembolso: reserva.admiteReembolso, tieneQr: reserva.reembolso?.tieneQr == true, local: local);

/// Banner de reembolso de un pedido: pide el QR bancario del cliente y muestra en qué quedó. Sirve para reservas y para compras;
/// lo único que cambia es el texto del aviso rojo ([textoAdjuntar]).
class BannerReembolsoPedido extends StatelessWidget {
  const BannerReembolsoPedido({super.key, required this.tipo, required this.local, required this.textoAdjuntar, required this.onAdjuntar});

  static const String textoAdjuntarReserva = 'Tu pedido fue cancelado. Adjunta tu QR para recibir el reembolso';
  static const String textoAdjuntarCompra = 'Tu compra fue rechazada. Adjunta tu QR para recibir el reembolso';
  static const String textoEnCola = 'Tu QR está guardado en el celular. Se enviará cuando vuelva la conexión';
  static const String textoRecibido = 'Recibimos tu QR. Te haremos la transferencia del reembolso';

  final TipoBannerReembolso? tipo;
  final QrLocal local;
  final String textoAdjuntar;

  /// Se llama al tocar el banner rojo (adjuntar o volver a adjuntar).
  final VoidCallback onAdjuntar;

  @override
  Widget build(BuildContext context) {
    final tipo = this.tipo;
    if (tipo == null) return const SizedBox.shrink();

    final (color, icono, texto, detalle) = switch (tipo) {
      TipoBannerReembolso.adjuntar => (Colors.red.shade700, Icons.qr_code_2, textoAdjuntar, null),
      TipoBannerReembolso.rechazado => (
          Colors.red.shade700,
          Icons.error_outline,
          'No pudimos usar tu QR. Adjunta otro para recibir el reembolso',
          local.motivo,
        ),
      TipoBannerReembolso.enCola => (Colors.orange.shade800, Icons.cloud_upload_outlined, textoEnCola, null),
      TipoBannerReembolso.recibido => (Colors.green.shade700, Icons.check_circle_outline, textoRecibido, null),
    };
    final tocable = tipo == TipoBannerReembolso.adjuntar || tipo == TipoBannerReembolso.rechazado;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        key: Key('banner_reembolso_${tipo.name}'),
        color: color,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: tocable ? onAdjuntar : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(icono, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(texto, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                      if (detalle != null && detalle.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(detalle, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                        ),
                    ],
                  ),
                ),
                if (tocable) const Icon(Icons.chevron_right, color: Colors.white),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Banner de reembolso de una reserva cancelada en "Mis Reservas".
class BannerReembolso extends StatelessWidget {
  const BannerReembolso({super.key, required this.reserva, required this.local, required this.onAdjuntar});

  static const String textoAdjuntar = BannerReembolsoPedido.textoAdjuntarReserva;
  static const String textoEnCola = BannerReembolsoPedido.textoEnCola;
  static const String textoRecibido = BannerReembolsoPedido.textoRecibido;

  final Reserva reserva;
  final QrLocal local;

  /// Se llama al tocar el banner rojo (adjuntar o volver a adjuntar).
  final VoidCallback onAdjuntar;

  @override
  Widget build(BuildContext context) => BannerReembolsoPedido(
        tipo: tipoBannerReembolso(reserva, local),
        local: local,
        textoAdjuntar: textoAdjuntar,
        onAdjuntar: onAdjuntar,
      );
}
