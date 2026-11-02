import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { AuthService } from '../../core/services/auth.service';
import { SucursalesService } from '../../core/services/sucursales.service';
import { TransferenciasService } from '../../core/services/transferencias.service';
import { Sucursal } from '../../core/models/sucursal.model';
import { InventarioItem } from '../../core/models/inventario.model';
import {
  AccionTransferencia,
  EstadoTransferencia,
  Transferencia,
} from '../../core/models/transferencia.model';

const ESTADOS: { valor: EstadoTransferencia; texto: string; clase: string }[] = [
  { valor: 'solicitada', texto: 'Solicitada', clase: 'est-pendiente' },
  { valor: 'aprobada', texto: 'Aprobada', clase: 'est-pendiente' },
  { valor: 'en_transito', texto: 'En tránsito', clase: 'est-transito' },
  { valor: 'recibida', texto: 'Recibida', clase: 'est-ok' },
  { valor: 'rechazada', texto: 'Rechazada', clase: 'est-fin' },
  { valor: 'cancelada', texto: 'Cancelada', clase: 'est-fin' },
];

const ACCIONES: Record<AccionTransferencia, { texto: string; clase: string; confirmar?: string }> = {
  aprobar: { texto: 'Aprobar', clase: 'btn-primary' },
  despachar: {
    texto: 'Despachar',
    clase: 'btn-primary',
    confirmar: 'Al despachar se descuenta el stock de la sucursal de origen. ¿Continuar?',
  },
  recibir: {
    texto: 'Confirmar recepción',
    clase: 'btn-primary',
    confirmar: 'Se va a sumar el stock en la sucursal de destino. ¿Llegó todo?',
  },
  rechazar: { texto: 'Rechazar', clase: 'btn-danger' },
  cancelar: { texto: 'Cancelar', clase: 'btn-secondary', confirmar: '¿Cancelar esta transferencia?' },
};

/** CU19 — Transferir stock entre sucursales (admin y encargados). */
@Component({
  selector: 'app-transferencias-page',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './transferencias-page.html',
  styleUrl: './transferencias-page.scss',
})
export class TransferenciasPage implements OnInit {
  private service = inject(TransferenciasService);
  private sucursalesService = inject(SucursalesService);
  private auth = inject(AuthService);

  readonly estados = ESTADOS;
  readonly acciones = ACCIONES;

  transferencias = signal<Transferencia[]>([]);
  sucursales = signal<Sucursal[]>([]);
  filtro = signal<EstadoTransferencia | null>(null);
  abierta = signal<number | null>(null);
  mostrarAlta = signal(false);
  guardando = signal(false);
  procesando = signal<number | null>(null);
  toast = signal<string | null>(null);
  toastIsError = signal(false);

  esAdmin = computed(() => this.auth.isAdmin());
  miSucursalId = computed(() => this.auth.currentUser()?.sucursal_id ?? null);
  sucursalesActivas = computed(() => this.sucursales().filter((s) => s.activa));
  pendientesDeMi = computed(() => this.transferencias().filter((t) => t.acciones.some((a) => a !== 'cancelar')).length);

  // Alta
  origenId: number | null = null;
  destinoId: number | null = null;
  motivo = '';
  stockOrigen = signal<InventarioItem[]>([]);
  cantidades: Record<number, number | null> = {};
  comentarios: Record<number, string> = {};

  ngOnInit() {
    this.sucursalesService.listar().subscribe((s) => this.sucursales.set(s));
    this.cargar();
  }

  cargar() {
    this.service.listar(this.filtro()).subscribe((data) => this.transferencias.set(data));
  }

  filtrar(estado: EstadoTransferencia | null) {
    this.filtro.set(estado);
    this.cargar();
  }

  estadoInfo(estado: EstadoTransferencia) {
    return ESTADOS.find((e) => e.valor === estado)!;
  }

  abrirAlta() {
    this.mostrarAlta.set(!this.mostrarAlta());
    if (!this.esAdmin() && this.miSucursalId()) {
      // Lo habitual para un encargado es pedir mercadería para su sucursal.
      this.destinoId = this.miSucursalId();
    }
  }

  cambiarOrigen() {
    this.cantidades = {};
    this.stockOrigen.set([]);
    if (this.origenId) {
      this.service.stockOrigen(this.origenId).subscribe((items) => this.stockOrigen.set(items));
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
      this.mostrarToast('Indicá la cantidad de al menos una prenda', true);
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
          this.stockOrigen.set([]);
          this.mostrarToast(`Transferencia #${t.id} creada`);
          this.abierta.set(t.id);
          this.cargar();
        },
        error: (err) => {
          this.guardando.set(false);
          this.mostrarToast(err.error?.detail || 'No se pudo crear la transferencia', true);
        },
      });
  }

  toggle(t: Transferencia) {
    this.abierta.set(this.abierta() === t.id ? null : t.id);
  }

  ejecutar(t: Transferencia, accion: AccionTransferencia) {
    const conf = ACCIONES[accion].confirmar;
    if (conf && !confirm(conf)) return;
    this.procesando.set(t.id);
    this.service.ejecutar(t.id, accion, this.comentarios[t.id]).subscribe({
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
    setTimeout(() => this.toast.set(null), 4000);
  }
}
