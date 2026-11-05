import { Component, OnDestroy, OnInit, computed, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { AuthService } from '../../core/services/auth.service';
import { CatalogoService } from '../../core/services/catalogo.service';
import { SucursalesService } from '../../core/services/sucursales.service';
import { TransferenciasService } from '../../core/services/transferencias.service';
import { Sucursal } from '../../core/models/sucursal.model';
import { Producto } from '../../core/models/catalogo.model';
import { InventarioItem } from '../../core/models/inventario.model';
import {
  AccionTransferencia,
  DisponibilidadTransferencia,
  EstadoTransferencia,
  Transferencia,
} from '../../core/models/transferencia.model';

const ESTADOS: { valor: EstadoTransferencia; texto: string; clase: string }[] = [
  { valor: 'solicitada', texto: 'Solicitada', clase: 'est-pendiente' },
  { valor: 'en_transito', texto: 'En tránsito', clase: 'est-transito' },
  { valor: 'recibida', texto: 'Recibida', clase: 'est-ok' },
  { valor: 'rechazada', texto: 'Rechazada', clase: 'est-fin' },
  { valor: 'cancelada', texto: 'Cancelada', clase: 'est-fin' },
];
const APROBADA = { valor: 'aprobada' as EstadoTransferencia, texto: 'Aprobada', clase: 'est-pendiente' };

const ACCIONES: Record<AccionTransferencia, { texto: string; clase: string; confirmar?: string }> = {
  enviar: {
    texto: 'Enviar',
    clase: 'btn-primary',
    confirmar: 'Al enviar se descuenta el inventario de la sucursal de origen. ¿Continuar?',
  },
  recibir: { texto: 'Confirmar recepción', clase: 'btn-primary' },
  rechazar: { texto: 'Rechazar', clase: 'btn-danger' },
  cancelar: { texto: 'Cancelar solicitud', clase: 'btn-secondary', confirmar: '¿Cancelar esta solicitud?' },
};

/** CU19 — Gestionar transferencia entre sucursales (admin y encargados). */
@Component({
  selector: 'app-transferencias-page',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './transferencias-page.html',
  styleUrl: './transferencias-page.scss',
})
export class TransferenciasPage implements OnInit, OnDestroy {
  private service = inject(TransferenciasService);
  private sucursalesService = inject(SucursalesService);
  private catalogo = inject(CatalogoService);
  private auth = inject(AuthService);

  readonly estados = ESTADOS;
  readonly acciones = ACCIONES;

  transferencias = signal<Transferencia[]>([]);
  sucursales = signal<Sucursal[]>([]);
  productos = signal<Producto[]>([]);
  filtro = signal<EstadoTransferencia | null>(null);
  abierta = signal<number | null>(null);
  mostrarAlta = signal(false);
  guardando = signal(false);
  procesando = signal<number | null>(null);
  toast = signal<string | null>(null);
  toastIsError = signal(false);
  /** CU19 1a: sin conexión se deshabilitan las transferencias. */
  enLinea = signal(navigator.onLine);

  esAdmin = computed(() => this.auth.isAdmin());
  miSucursalId = computed(() => this.auth.currentUser()?.sucursal_id ?? null);
  sucursalesActivas = computed(() => this.sucursales().filter((s) => s.activa));
  pendientesDeMi = computed(() => this.transferencias().filter((t) => t.acciones.some((a) => a !== 'cancelar')).length);

  // Nueva solicitud
  productoBuscado: number | null = null;
  disponibilidad = signal<DisponibilidadTransferencia[] | null>(null);
  origenId: number | null = null;
  destinoId: number | null = null;
  motivo = '';
  stockOrigen = signal<InventarioItem[]>([]);
  cantidades: Record<number, number | null> = {};
  comentarios: Record<number, string> = {};
  /** Recepción: lo que llegó de cada línea (por defecto, lo enviado). */
  recibidas: Record<number, number> = {};

  private alCambiarRed = () => this.enLinea.set(navigator.onLine);

  ngOnInit() {
    window.addEventListener('online', this.alCambiarRed);
    window.addEventListener('offline', this.alCambiarRed);
    this.sucursalesService.listar().subscribe((s) => this.sucursales.set(s));
    this.cargar();
  }

  ngOnDestroy() {
    window.removeEventListener('online', this.alCambiarRed);
    window.removeEventListener('offline', this.alCambiarRed);
  }

  cargar() {
    this.service.listar(this.filtro()).subscribe((data) => this.transferencias.set(data));
  }

  filtrar(estado: EstadoTransferencia | null) {
    this.filtro.set(estado);
    this.cargar();
  }

  estadoInfo(estado: EstadoTransferencia) {
    return ESTADOS.find((e) => e.valor === estado) ?? APROBADA;
  }

  abrirAlta() {
    this.mostrarAlta.set(!this.mostrarAlta());
    // El encargado de destino pide prendas para su propia sucursal.
    if (!this.esAdmin() && this.miSucursalId()) this.destinoId = this.miSucursalId();
    if (!this.productos().length) this.catalogo.listarProductos().subscribe((p) => this.productos.set(p));
  }

  /** Paso 2: sucursales de la empresa con existencia de la prenda buscada. */
  buscarDisponibilidad() {
    this.disponibilidad.set(null);
    if (!this.productoBuscado) return;
    this.service.disponibilidad(this.productoBuscado).subscribe((d) =>
      this.disponibilidad.set(d.filter((x) => x.sucursal_id !== this.destinoId)),
    );
  }

  sucursalesConExistencia(): { id: number; nombre: string; filas: DisponibilidadTransferencia[] }[] {
    const grupos = new Map<number, { id: number; nombre: string; filas: DisponibilidadTransferencia[] }>();
    for (const fila of this.disponibilidad() ?? []) {
      const g = grupos.get(fila.sucursal_id) ?? { id: fila.sucursal_id, nombre: fila.nombre_sucursal, filas: [] };
      g.filas.push(fila);
      grupos.set(fila.sucursal_id, g);
    }
    return [...grupos.values()];
  }

  pedirA(sucursalId: number) {
    this.origenId = sucursalId;
    this.cambiarOrigen();
  }

  cambiarOrigen() {
    this.cantidades = {};
    this.stockOrigen.set([]);
    if (this.origenId) {
      this.service.stockOrigen(this.origenId).subscribe((items) => {
        // La prenda buscada primero.
        const buscado = this.productoBuscado;
        this.stockOrigen.set([...items].sort((a, b) => Number(b.producto_id === buscado) - Number(a.producto_id === buscado)));
      });
    }
  }

  totalSeleccionado(): number {
    return Object.values(this.cantidades).reduce<number>((acc, v) => acc + (Number(v) || 0), 0);
  }

  crear() {
    if (!this.origenId || !this.destinoId) return;
    const items = Object.entries(this.cantidades)
      .filter(([, c]) => Number(c) > 0)
      .map(([id, c]) => ({ inventario_id: Number(id), cantidad: Number(c) }));
    if (!items.length) {
      this.mostrarToast('Indique la cantidad de al menos una prenda', true);
      return;
    }
    this.guardando.set(true);
    this.service
      .crear({ sucursal_origen_id: this.origenId, sucursal_destino_id: this.destinoId, motivo: this.motivo || null, items })
      .subscribe({
        next: (t) => {
          this.guardando.set(false);
          this.mostrarAlta.set(false);
          this.origenId = null;
          this.motivo = '';
          this.cantidades = {};
          this.productoBuscado = null;
          this.disponibilidad.set(null);
          this.stockOrigen.set([]);
          this.mostrarToast(`Solicitud #${t.id} registrada`);
          this.abierta.set(t.id);
          this.cargar();
        },
        error: (err) => {
          // 4a: el mensaje indica la cantidad disponible para ajustarla.
          this.guardando.set(false);
          this.mostrarToast(err.error?.detail || 'No se pudo registrar la solicitud', true);
          if (this.origenId) this.service.stockOrigen(this.origenId).subscribe((i) => this.stockOrigen.set(i));
        },
      });
  }

  toggle(t: Transferencia) {
    const abrir = this.abierta() !== t.id;
    this.abierta.set(abrir ? t.id : null);
    if (abrir) for (const i of t.items) this.recibidas[i.id] ??= i.cantidad;
  }

  ejecutar(t: Transferencia, accion: AccionTransferencia) {
    const comentario = this.comentarios[t.id]?.trim();
    if (accion === 'rechazar' && !comentario) {
      this.mostrarToast('Escriba el motivo del rechazo', true);
      return;
    }
    let recibidas: { item_id: number; cantidad_recibida: number }[] = [];
    if (accion === 'recibir') {
      recibidas = t.items.map((i) => ({ item_id: i.id, cantidad_recibida: Number(this.recibidas[i.id] ?? i.cantidad) }));
      const faltan = recibidas.reduce((acc, r, k) => acc + (t.items[k].cantidad - r.cantidad_recibida), 0);
      const pregunta = faltan > 0
        ? `Faltan ${faltan} unidad(es): se va a registrar la diferencia como observación. ¿Confirmar la recepción?`
        : 'Se suman las prendas al inventario de su sucursal. ¿Confirmar la recepción?';
      if (!confirm(pregunta)) return;
    } else {
      const conf = ACCIONES[accion].confirmar;
      if (conf && !confirm(conf)) return;
    }
    this.procesando.set(t.id);
    this.service.ejecutar(t.id, accion, comentario, recibidas).subscribe({
      next: (actualizada) => {
        this.procesando.set(null);
        this.comentarios[t.id] = '';
        this.transferencias.update((lista) => lista.map((x) => (x.id === t.id ? actualizada : x)));
        this.mostrarToast(`Transferencia #${t.id}: ${this.estadoInfo(actualizada.estado).texto.toLowerCase()}`);
      },
      error: (err) => {
        this.procesando.set(null);
        this.mostrarToast(err.error?.detail || 'No se pudo completar la acción', true);
        this.cargar();
      },
    });
  }

  private mostrarToast(msg: string, isError = false) {
    this.toast.set(msg);
    this.toastIsError.set(isError);
    setTimeout(() => this.toast.set(null), 6000);
  }
}
