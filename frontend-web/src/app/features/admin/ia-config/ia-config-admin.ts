import { Component, OnInit, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { IconComponent } from '../../../core/components/icon/icon';
import { IaService } from '../../../core/services/ia.service';
import { ConfiguracionIA } from '../../../core/models/ia.model';

interface Preset {
  nombre: string;
  base_url: string;
  modelo: string;
  ayuda: string;
}

const PRESETS: Preset[] = [
  {
    nombre: 'Ollama (local)',
    base_url: 'http://host.docker.internal:11434/v1',
    modelo: 'llama3.2:1b',
    ayuda: 'Requiere tener Ollama corriendo en tu máquina con el modelo ya descargado (ollama pull llama3.2:1b). No necesita API key.',
  },
  {
    nombre: 'OpenAI (nube)',
    base_url: 'https://api.openai.com/v1',
    modelo: 'gpt-4o-mini',
    ayuda: 'Requiere una API key de platform.openai.com con crédito cargado.',
  },
  {
    nombre: 'Groq (nube, gratis, rápido)',
    base_url: 'https://api.groq.com/openai/v1',
    modelo: 'llama-3.1-8b-instant',
    ayuda: 'Requiere una API key gratuita de console.groq.com. Responde en menos de 1 segundo.',
  },
];

@Component({
  selector: 'app-ia-config-admin',
  standalone: true,
  imports: [CommonModule, FormsModule, IconComponent],
  templateUrl: './ia-config-admin.html',
  styleUrl: './ia-config-admin.scss',
})
export class IaConfigAdmin implements OnInit {
  private iaService = inject(IaService);

  presets = PRESETS;
  cargando = signal(true);
  guardando = signal(false);
  probando = signal(false);

  apiKeyConfigurada = signal(false);
  resultadoPrueba = signal<{ ok: boolean; mensaje: string } | null>(null);

  form = {
    base_url: '',
    modelo: '',
    api_key: '',
  };

  ngOnInit() {
    this.iaService.obtenerConfiguracion().subscribe({
      next: (data: ConfiguracionIA) => {
        this.form.base_url = data.base_url;
        this.form.modelo = data.modelo;
        this.apiKeyConfigurada.set(data.api_key_configurada);
        this.cargando.set(false);
      },
      error: () => this.cargando.set(false),
    });
  }

  aplicarPreset(preset: Preset) {
    this.form.base_url = preset.base_url;
    this.form.modelo = preset.modelo;
  }

  guardar() {
    this.guardando.set(true);
    this.resultadoPrueba.set(null);
    this.iaService
      .actualizarConfiguracion({
        base_url: this.form.base_url.trim(),
        modelo: this.form.modelo.trim(),
        api_key: this.form.api_key.trim() || null,
      })
      .subscribe({
        next: (data) => {
          this.apiKeyConfigurada.set(data.api_key_configurada);
          this.form.api_key = '';
          this.guardando.set(false);
        },
        error: () => this.guardando.set(false),
      });
  }

  probarConexion() {
    this.probando.set(true);
    this.resultadoPrueba.set(null);
    this.iaService.probarConfiguracion().subscribe({
      next: (res) => {
        this.resultadoPrueba.set({
          ok: res.ok,
          mensaje: res.ok ? (res.respuesta ?? '(sin texto)') : (res.error ?? 'Error desconocido'),
        });
        this.probando.set(false);
      },
      error: (err) => {
        this.resultadoPrueba.set({
          ok: false,
          mensaje: err.error?.detail || 'No se pudo probar la conexión',
        });
        this.probando.set(false);
      },
    });
  }
}
