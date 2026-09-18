import { Component, OnInit, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { ActivatedRoute, Router } from '@angular/router';
import { IconComponent } from '../../../core/components/icon/icon';
import {
  PagosPublicosService,
  PagoPublico,
} from '../../../core/services/pagos-publicos.service';

@Component({
  selector: 'app-pago-comprobante',
  standalone: true,
  imports: [CommonModule, IconComponent],
  templateUrl: './pago-comprobante.html',
  styleUrl: './pago-comprobante.scss',
})
export class PagoComprobante implements OnInit {
  private route = inject(ActivatedRoute);
  private router = inject(Router);
  private pagosService = inject(PagosPublicosService);

  pago = signal<PagoPublico | null>(null);
  cargando = signal<boolean>(true);
  subiendo = signal<boolean>(false);
  archivoSeleccionado = signal<File | null>(null);
  previewUrl = signal<string | null>(null);
  error = signal<string | null>(null);
  enviado = signal<boolean>(false);

  ngOnInit() {
    const idParam = this.route.snapshot.paramMap.get('id');
    const pagoId = Number(idParam);
    if (!idParam || isNaN(pagoId)) {
      this.error.set('Identificador de pago inválido');
      this.cargando.set(false);
      return;
    }

    this.pagosService.obtener(pagoId).subscribe({
      next: (data) => {
        this.pago.set(data);
        if (data.ya_tiene_comprobante) {
          this.enviado.set(true);
        }
        this.cargando.set(false);
      },
      error: (err) => {
        const msg = err.error?.detail || 'No se pudo cargar la información del pago.';
        this.error.set(msg);
        this.cargando.set(false);
      },
    });
  }

  onFileSelected(event: Event) {
    const input = event.target as HTMLInputElement;
    if (!input.files || input.files.length === 0) return;

    const file = input.files[0];

    if (!file.type.startsWith('image/')) {
      this.error.set('Por favor seleccioná un archivo de imagen válido (PNG, JPG, WEBP).');
      return;
    }

    if (file.size > 10 * 1024 * 1024) {
      this.error.set('La imagen supera el límite de 10 MB.');
      return;
    }

    this.error.set(null);
    this.archivoSeleccionado.set(file);

    if (this.previewUrl()) {
      URL.revokeObjectURL(this.previewUrl()!);
    }
    this.previewUrl.set(URL.createObjectURL(file));
  }

  enviarComprobante() {
    const file = this.archivoSeleccionado();
    const currentPago = this.pago();
    if (!file || !currentPago) {
      this.error.set('Debes seleccionar o tomar una foto de tu comprobante.');
      return;
    }

    this.subiendo.set(true);
    this.error.set(null);

    this.pagosService.subirComprobante(currentPago.id, file).subscribe({
      next: () => {
        this.subiendo.set(false);
        this.enviado.set(true);
      },
      error: (err) => {
        this.subiendo.set(false);
        const msg = err.error?.detail || 'Ocurrió un error al subir el comprobante.';
        this.error.set(msg);
      },
    });
  }

  nuevaFoto(fileInput: HTMLInputElement) {
    if (this.previewUrl()) {
      URL.revokeObjectURL(this.previewUrl()!);
    }
    this.archivoSeleccionado.set(null);
    this.previewUrl.set(null);
    this.error.set(null);
    fileInput.value = '';
    fileInput.click();
  }
}
