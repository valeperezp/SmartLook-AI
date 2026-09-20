import { Component, ElementRef, ViewChild, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { inject } from '@angular/core';
import { IaService } from '../../services/ia.service';
import { ReportesChatService } from '../../services/reportes-chat.service';
import { IconComponent } from '../icon/icon';

interface MensajeChat {
  autor: 'usuario' | 'bot';
  texto: string;
}

const SUGERENCIAS_INICIALES = [
  'Generame un resumen del día',
  '¿Qué productos tienen stock bajo?',
  '¿Cómo van las reservas esta semana?',
];

/**
 * Asistente de IA para reportes: disponible solo para admin/encargado (los dos
 * roles con acceso a Reportes). Es la tercera vía para "generar un reporte",
 * junto a la descarga en PDF y Excel — acá se pide en lenguaje natural (texto
 * o voz) y la IA lo redacta en el chat, siempre anclada a datos reales.
 */
@Component({
  selector: 'app-reportes-chat-widget',
  standalone: true,
  imports: [CommonModule, FormsModule, IconComponent],
  templateUrl: './reportes-chat-widget.html',
  styleUrl: './reportes-chat-widget.scss',
})
export class ReportesChatWidget {
  private iaService = inject(IaService);
  reportesChatService = inject(ReportesChatService);

  @ViewChild('mensajesBox') private mensajesBox?: ElementRef<HTMLDivElement>;

  enviando = signal(false);
  inputTexto = signal('');

  vozDisponible = signal(false);
  escuchando = signal(false);
  private reconocimiento: any = null;
  mensajes = signal<MensajeChat[]>([
    {
      autor: 'bot',
      texto:
        '¡Hola! Soy tu asistente de reportes. Pedime lo que necesites saber del negocio ' +
        '(reservas, inventario, productos, tendencias) y te lo redacto al instante, con datos reales. ' +
        'Si necesitás un archivo formal, usá los botones de Exportar PDF/Excel de esta misma página.',
    },
  ]);
  sugerenciasActuales = signal<string[]>(SUGERENCIAS_INICIALES);

  constructor() {
    const SpeechRecognitionCtor =
      (window as any).SpeechRecognition || (window as any).webkitSpeechRecognition;
    if (SpeechRecognitionCtor) {
      this.vozDisponible.set(true);
      this.reconocimiento = new SpeechRecognitionCtor();
      this.reconocimiento.lang = 'es-419';
      this.reconocimiento.interimResults = true;
      this.reconocimiento.maxAlternatives = 1;

      this.reconocimiento.onresult = (event: any) => {
        const transcripcion = Array.from(event.results as any)
          .map((r: any) => r[0].transcript)
          .join('');
        this.inputTexto.set(transcripcion);

        const ultimo = event.results[event.results.length - 1];
        if (ultimo?.isFinal) {
          this.escuchando.set(false);
          this.enviarDesdeInput();
        }
      };

      this.reconocimiento.onerror = () => this.escuchando.set(false);
      this.reconocimiento.onend = () => this.escuchando.set(false);
    }
  }

  alternarEscucha() {
    if (!this.vozDisponible() || this.enviando()) return;

    if (this.escuchando()) {
      this.reconocimiento.stop();
      this.escuchando.set(false);
      return;
    }

    this.inputTexto.set('');
    this.escuchando.set(true);
    try {
      this.reconocimiento.start();
    } catch {
      this.escuchando.set(false);
    }
  }

  toggle() {
    this.reportesChatService.toggle();
  }

  cerrar() {
    this.reportesChatService.cerrar();
    if (this.escuchando()) {
      this.reconocimiento?.stop();
      this.escuchando.set(false);
    }
  }

  enviarSugerencia(texto: string) {
    this.enviarMensaje(texto);
  }

  enviarDesdeInput() {
    this.enviarMensaje(this.inputTexto());
  }

  private enviarMensaje(textoCrudo: string) {
    const texto = textoCrudo.trim();
    if (!texto || this.enviando()) return;

    // Los últimos turnos ya en pantalla, ANTES de agregar este mensaje nuevo — le dan
    // contexto a la IA para entender seguimientos como "y el mes pasado?".
    const historial = this.mensajes().slice(-6);

    this.mensajes.update((arr) => [...arr, { autor: 'usuario', texto }]);
    this.inputTexto.set('');
    this.enviando.set(true);
    this.scrollAbajo();

    const sucursalId = this.reportesChatService.sucursalId();
    this.iaService.chatReportes(texto, historial, sucursalId).subscribe({
      next: (res) => {
        this.mensajes.update((arr) => [...arr, { autor: 'bot', texto: res.respuesta }]);
        this.sugerenciasActuales.set(res.sugerencias?.length ? res.sugerencias : SUGERENCIAS_INICIALES);
        this.enviando.set(false);
        this.scrollAbajo();
      },
      error: () => {
        this.mensajes.update((arr) => [
          ...arr,
          { autor: 'bot', texto: 'Uy, tuve un problema para responderte. ¿Podés intentar de nuevo?' },
        ]);
        this.enviando.set(false);
        this.scrollAbajo();
      },
    });
  }

  private scrollAbajo() {
    setTimeout(() => {
      const el = this.mensajesBox?.nativeElement;
      if (el) el.scrollTop = el.scrollHeight;
    }, 0);
  }
}
