import { Component, ElementRef, ViewChild, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { inject } from '@angular/core';
import { IaService } from '../../services/ia.service';
import { IconComponent } from '../icon/icon';

interface MensajeChat {
  autor: 'usuario' | 'bot';
  texto: string;
}

const SUGERENCIAS_INICIALES = [
  '¿Qué me recomendás?',
  '¿Cuáles son mis reservas?',
  '¿Dónde están las sucursales?',
  'Busco una camisa',
];

@Component({
  selector: 'app-chat-widget',
  standalone: true,
  imports: [CommonModule, FormsModule, IconComponent],
  templateUrl: './chat-widget.html',
  styleUrl: './chat-widget.scss',
})
export class ChatWidget {
  private iaService = inject(IaService);

  @ViewChild('mensajesBox') private mensajesBox?: ElementRef<HTMLDivElement>;

  abierto = signal(false);
  enviando = signal(false);
  inputTexto = signal('');

  vozDisponible = signal(false);
  escuchando = signal(false);
  private reconocimiento: any = null;
  mensajes = signal<MensajeChat[]>([
    {
      autor: 'bot',
      texto:
        '¡Hola! Soy el asistente virtual de SmartLook-AI. Puedo ayudarte a buscar prendas, ' +
        'darte recomendaciones, o contarte sobre tus reservas y sucursales. ¿En qué te ayudo?',
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
    this.abierto.update((v) => !v);
  }

  cerrar() {
    this.abierto.set(false);
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
    // contexto al backend/IA para entender seguimientos como "dame más detalles".
    const historial = this.mensajes().slice(-6);

    this.mensajes.update((arr) => [...arr, { autor: 'usuario', texto }]);
    this.inputTexto.set('');
    this.enviando.set(true);
    this.scrollAbajo();

    this.iaService.chat(texto, historial).subscribe({
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
