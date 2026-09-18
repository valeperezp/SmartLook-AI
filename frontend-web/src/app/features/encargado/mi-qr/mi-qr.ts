import { Component, OnInit, inject, signal } from '@angular/core';
import { CommonModule, DatePipe } from '@angular/common';
import { IconComponent } from '../../../core/components/icon/icon';
import { AuthService } from '../../../core/services/auth.service';
import { SucursalQRService } from '../../../core/services/sucursal-qr.service';
import { SucursalQR } from '../../../core/models/sucursal-qr.model';

@Component({
  selector: 'app-mi-qr',
  standalone: true,
  imports: [CommonModule, IconComponent, DatePipe],
  templateUrl: './mi-qr.html',
  styleUrl: './mi-qr.scss',
})
export class MiQR implements OnInit {
  private auth = inject(AuthService);
  private qrService = inject(SucursalQRService);

  user = this.auth.currentUser;
  qr = signal<SucursalQR | null>(null);
  cargando = signal<boolean>(true);
  subiendo = signal<boolean>(false);
  toast = signal<string | null>(null);
  toastIsError = signal<boolean>(false);
  confirmacionDesactivar = signal<boolean>(false);

  ngOnInit() {
    this.cargarQR();
  }

  cargarQR() {
    const sucursalId = this.user()?.sucursal_id;
    if (!sucursalId) {
      this.cargando.set(false);
      return;
    }

    this.cargando.set(true);
    this.qrService.obtener(sucursalId).subscribe({
      next: (data) => {
        this.qr.set(data);
        this.cargando.set(false);
      },
      error: (err) => {
        if (err.status === 404) {
          this.qr.set(null);
        } else {
          console.error('Error al cargar QR', err);
        }
        this.cargando.set(false);
      },
    });
  }

  abrirFileDialog(fileInput: HTMLInputElement) {
    fileInput.click();
  }

  onFileSelected(event: Event) {
    const input = event.target as HTMLInputElement;
    if (input.files && input.files.length > 0) {
      const file = input.files[0];
      this.subirQR(file);
      input.value = '';
    }
  }

  subirQR(archivo: File) {
    const sucursalId = this.user()?.sucursal_id;
    if (!sucursalId) {
      this.mostrarToast('No tienes una sucursal asignada', true);
      return;
    }

    const allowed = ['image/png', 'image/jpeg', 'image/jpg', 'image/webp'];
    if (!allowed.includes(archivo.type)) {
      this.mostrarToast('Formato no permitido. Usá PNG, JPG o WEBP', true);
      return;
    }

    if (archivo.size > 5 * 1024 * 1024) {
      this.mostrarToast('El archivo supera los 5 MB', true);
      return;
    }

    this.subiendo.set(true);
    this.qrService.subir(sucursalId, archivo).subscribe({
      next: (data) => {
        this.qr.set(data);
        this.subiendo.set(false);
        this.mostrarToast('Código QR guardado y activado exitosamente');
      },
      error: (err) => {
        this.subiendo.set(false);
        const msg = err.error?.detail || 'Error al subir el código QR';
        this.mostrarToast(msg, true);
      },
    });
  }

  desactivarQR() {
    const sucursalId = this.user()?.sucursal_id;
    if (!sucursalId) return;

    this.cargando.set(true);
    this.qrService.desactivar(sucursalId).subscribe({
      next: () => {
        this.qr.set(null);
        this.confirmacionDesactivar.set(false);
        this.cargando.set(false);
        this.mostrarToast('Código QR desactivado');
      },
      error: (err) => {
        this.cargando.set(false);
        this.confirmacionDesactivar.set(false);
        const msg = err.error?.detail || 'Error al desactivar el código QR';
        this.mostrarToast(msg, true);
      },
    });
  }

  mostrarToast(msg: string, isError = false) {
    this.toast.set(msg);
    this.toastIsError.set(isError);
    setTimeout(() => {
      if (this.toast() === msg) {
        this.toast.set(null);
      }
    }, 4000);
  }
}
