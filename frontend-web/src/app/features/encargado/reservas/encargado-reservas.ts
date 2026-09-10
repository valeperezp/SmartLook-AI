import { Component, OnInit, inject, signal, computed } from '@angular/core';
import { CommonModule, DatePipe } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ReservasService } from '../../../core/services/reservas.service';
import { AuthService } from '../../../core/services/auth.service';
import { Reserva } from '../../../core/models/reserva.model';
import { IconComponent } from '../../../core/components/icon/icon';

@Component({
  selector: 'app-encargado-reservas',
  standalone: true,
  imports: [CommonModule, DatePipe, FormsModule, IconComponent],
  templateUrl: './encargado-reservas.html',
  styleUrl: './encargado-reservas.scss',
})
export class EncargadoReservas implements OnInit {
  private reservasService = inject(ReservasService);
  auth = inject(AuthService);

  reservas = signal<Reserva[]>([]);
  cargando = signal<boolean>(true);
  filtroEstado = signal<string>('todas');
  busqueda = signal<string>('');
  reservaSeleccionada = signal<Reserva | null>(null);
  modalDetalleAbierto = signal<boolean>(false);
  procesando = signal<boolean>(false);
  toast = signal<string | null>(null);
  toastIsError = signal<boolean>(false);

  private toastTimeout: ReturnType<typeof setTimeout> | null = null;

  reservasFiltradas = computed(() => {
    const estado = this.filtroEstado();
    const q = this.busqueda().toLowerCase().trim();

    return this.reservas().filter((r) => {
      const matchEstado = estado === 'todas' || r.estado === estado;
      const matchBusqueda =
        !q ||
        (r.nombre_cliente && r.nombre_cliente.toLowerCase().includes(q)) ||
        (r.email_cliente && r.email_cliente.toLowerCase().includes(q)) ||
        String(r.id).includes(q);
      return matchEstado && matchBusqueda;
    });
  });

  totalPendientes = computed(
    () => this.reservas().filter((r) => r.estado === 'pendiente').length
  );
  totalConfirmadas = computed(
    () => this.reservas().filter((r) => r.estado === 'confirmada').length
  );
  totalAtendidas = computed(
    () => this.reservas().filter((r) => r.estado === 'atendida').length
  );
  totalCanceladas = computed(
    () => this.reservas().filter((r) => r.estado === 'cancelada').length
  );

  ngOnInit() {
    this.cargar();
  }

  cargar() {
    this.cargando.set(true);
    this.reservasService.miSucursal().subscribe({
      next: (data) => {
        this.reservas.set(data);
        this.cargando.set(false);
      },
      error: (err) => {
        this.cargando.set(false);
        this.mostrarToast('Error al cargar reservas de la sucursal', true);
      },
    });
  }

  abrirDetalle(r: Reserva) {
    this.reservaSeleccionada.set(r);
    this.modalDetalleAbierto.set(true);
  }

  cerrarDetalle() {
    this.modalDetalleAbierto.set(false);
    this.reservaSeleccionada.set(null);
  }

  confirmarReserva(r: Reserva) {
    if (!confirm(`¿Confirmar la reserva #${r.id}?`)) return;

    const estadoAnterior = r.estado;
    // Actualización optimista: cambia el estado en el signal inmediatamente (0ms)
    this.reservas.update((lista) =>
      lista.map((item) => (item.id === r.id ? { ...item, estado: 'confirmada' } : item))
    );
    if (this.reservaSeleccionada()?.id === r.id) {
      this.reservaSeleccionada.update((item) =>
        item ? { ...item, estado: 'confirmada' } : null
      );
    }

    this.procesando.set(true);
    this.reservasService.cambiarEstado(r.id, 'confirmada').subscribe({
      next: (reservaActualizada) => {
        // Reemplaza con la respuesta real del backend
        this.reservas.update((lista) =>
          lista.map((item) => (item.id === reservaActualizada.id ? reservaActualizada : item))
        );
        if (this.reservaSeleccionada()?.id === reservaActualizada.id) {
          this.reservaSeleccionada.set(reservaActualizada);
        }
        this.procesando.set(false);
        this.mostrarToast(`Reserva #${r.id} confirmada`, false);
      },
      error: (err) => {
        // Revierte si falla
        this.reservas.update((lista) =>
          lista.map((item) => (item.id === r.id ? { ...item, estado: estadoAnterior } : item))
        );
        if (this.reservaSeleccionada()?.id === r.id) {
          this.reservaSeleccionada.update((item) =>
            item ? { ...item, estado: estadoAnterior } : null
          );
        }
        this.procesando.set(false);
        this.mostrarToast(err?.error?.detail || 'Error al confirmar', true);
      },
    });
  }

  atenderReserva(r: Reserva) {
    if (
      !confirm(
        `¿Marcar la Reserva #${r.id} como ATENDIDA? (El cliente retira las prendas).`
      )
    ) {
      return;
    }

    const estadoAnterior = r.estado;
    // Actualización optimista: cambia el estado en el signal inmediatamente (0ms)
    this.reservas.update((lista) =>
      lista.map((item) => (item.id === r.id ? { ...item, estado: 'atendida' } : item))
    );
    if (this.reservaSeleccionada()?.id === r.id) {
      this.reservaSeleccionada.update((item) =>
        item ? { ...item, estado: 'atendida' } : null
      );
    }

    this.procesando.set(true);
    this.reservasService.cambiarEstado(r.id, 'atendida').subscribe({
      next: (reservaActualizada) => {
        this.reservas.update((lista) =>
          lista.map((item) => (item.id === reservaActualizada.id ? reservaActualizada : item))
        );
        if (this.reservaSeleccionada()?.id === reservaActualizada.id) {
          this.reservaSeleccionada.set(reservaActualizada);
        }
        this.procesando.set(false);
        this.mostrarToast(`Reserva #${r.id} marcada como ATENDIDA`, false);
      },
      error: (err) => {
        this.reservas.update((lista) =>
          lista.map((item) => (item.id === r.id ? { ...item, estado: estadoAnterior } : item))
        );
        if (this.reservaSeleccionada()?.id === r.id) {
          this.reservaSeleccionada.update((item) =>
            item ? { ...item, estado: estadoAnterior } : null
          );
        }
        this.procesando.set(false);
        this.mostrarToast(err?.error?.detail || 'Error al atender la reserva', true);
      },
    });
  }

  cancelarReserva(r: Reserva) {
    if (
      !confirm(
        `¿Cancelar la Reserva #${r.id}? El stock reservado se liberará a inventario disponible.`
      )
    ) {
      return;
    }

    const estadoAnterior = r.estado;
    // Actualización optimista: cambia el estado en el signal inmediatamente (0ms)
    this.reservas.update((lista) =>
      lista.map((item) => (item.id === r.id ? { ...item, estado: 'cancelada' } : item))
    );
    if (this.reservaSeleccionada()?.id === r.id) {
      this.reservaSeleccionada.update((item) =>
        item ? { ...item, estado: 'cancelada' } : null
      );
    }

    this.procesando.set(true);
    this.reservasService.cambiarEstado(r.id, 'cancelada').subscribe({
      next: (reservaActualizada) => {
        this.reservas.update((lista) =>
          lista.map((item) => (item.id === reservaActualizada.id ? reservaActualizada : item))
        );
        if (this.reservaSeleccionada()?.id === reservaActualizada.id) {
          this.reservaSeleccionada.set(reservaActualizada);
        }
        this.procesando.set(false);
        this.mostrarToast(`Reserva #${r.id} cancelada y stock devuelto`, false);
      },
      error: (err) => {
        this.reservas.update((lista) =>
          lista.map((item) => (item.id === r.id ? { ...item, estado: estadoAnterior } : item))
        );
        if (this.reservaSeleccionada()?.id === r.id) {
          this.reservaSeleccionada.update((item) =>
            item ? { ...item, estado: estadoAnterior } : null
          );
        }
        this.procesando.set(false);
        this.mostrarToast(err?.error?.detail || 'Error al cancelar la reserva', true);
      },
    });
  }

  mostrarToast(msg: string, isError = false) {
    if (this.toastTimeout) {
      clearTimeout(this.toastTimeout);
    }
    this.toast.set(msg);
    this.toastIsError.set(isError);
    this.toastTimeout = setTimeout(() => {
      this.toast.set(null);
    }, 3500);
  }

  claseBadgeEstado(estado: string): string {
    switch (estado?.toLowerCase()) {
      case 'pendiente':
        return 'badge-warning';
      case 'confirmada':
        return 'badge-info';
      case 'atendida':
        return 'badge-success';
      case 'cancelada':
        return 'badge-danger';
      default:
        return 'badge-muted';
    }
  }
}
