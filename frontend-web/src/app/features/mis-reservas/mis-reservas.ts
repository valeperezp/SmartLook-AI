import { Component, OnInit, inject, signal } from '@angular/core';
import { CommonModule, DatePipe } from '@angular/common';
import { RouterLink } from '@angular/router';
import { ReservasService } from '../../core/services/reservas.service';
import { AuthService } from '../../core/services/auth.service';
import { Reserva } from '../../core/models/reserva.model';
import { IconComponent } from '../../core/components/icon/icon';

@Component({
  selector: 'app-mis-reservas',
  standalone: true,
  imports: [CommonModule, DatePipe, RouterLink, IconComponent],
  templateUrl: './mis-reservas.html',
  styleUrl: './mis-reservas.scss',
})
export class MisReservas implements OnInit {
  private reservasService = inject(ReservasService);
  auth = inject(AuthService);

  reservas = signal<Reserva[]>([]);
  cargando = signal<boolean>(true);
  reservaSeleccionada = signal<Reserva | null>(null);
  modalDetalleAbierto = signal<boolean>(false);
  cancelando = signal<boolean>(false);
  toast = signal<string | null>(null);
  toastIsError = signal<boolean>(false);

  private toastTimeout: ReturnType<typeof setTimeout> | null = null;

  ngOnInit() {
    this.cargarReservas();
  }

  cargarReservas() {
    this.cargando.set(true);
    this.reservasService.misReservas().subscribe({
      next: (data) => {
        this.reservas.set(data);
        this.cargando.set(false);
      },
      error: (err) => {
        this.cargando.set(false);
        this.mostrarToast('Error al cargar las reservas', true);
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

  cancelarReserva(r: Reserva) {
    if (
      !confirm(
        `¿Estás seguro de cancelar la Reserva #${r.id}? El stock reservado se liberará inmediatamente.`
      )
    ) {
      return;
    }

    this.cancelando.set(true);
    this.reservasService.cancelar(r.id).subscribe({
      next: (actualizada) => {
        this.cancelando.set(false);
        this.mostrarToast(`Reserva #${r.id} cancelada con éxito`, false);
        if (this.reservaSeleccionada()?.id === r.id) {
          this.reservaSeleccionada.set(actualizada);
        }
        this.cargarReservas();
      },
      error: (err) => {
        this.cancelando.set(false);
        const msg = err.error?.detail || 'No se pudo cancelar la reserva';
        this.mostrarToast(msg, true);
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
      case 'atendida':
        return 'badge-success';
      case 'cancelada':
        return 'badge-danger';
      default:
        return 'badge-muted';
    }
  }
}
