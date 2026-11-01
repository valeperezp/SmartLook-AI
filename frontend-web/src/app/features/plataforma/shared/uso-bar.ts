import { Component, Input, computed, signal } from '@angular/core';
import { UsoRecurso } from '../../../core/models/empresa.model';

/** Barra "usados / límite" de un recurso del plan (CU4). */
@Component({
  selector: 'app-uso-bar',
  standalone: true,
  template: `
    <div class="uso">
      <div class="uso-top">
        <span class="uso-label">{{ label }}</span>
        <span class="uso-num" [class.lleno]="lleno()">
          {{ uso().usados }} / {{ uso().limite ?? '∞' }}
        </span>
      </div>
      <div class="uso-track">
        <div class="uso-fill" [class.lleno]="lleno()" [style.width.%]="porcentaje()"></div>
      </div>
    </div>
  `,
  styles: `
    .uso { min-width: 0; }
    .uso-top { display: flex; justify-content: space-between; gap: 0.5rem; font-size: 0.8rem; margin-bottom: 0.3rem; }
    .uso-label { color: var(--text-secondary); }
    .uso-num { font-variant-numeric: tabular-nums; font-weight: 600; }
    .uso-num.lleno { color: var(--danger); }
    .uso-track { height: 6px; border-radius: 999px; background: var(--border-color); overflow: hidden; }
    .uso-fill { height: 100%; background: var(--success); border-radius: inherit; transition: width 0.3s ease; }
    .uso-fill.lleno { background: var(--danger); }
  `,
})
export class UsoBar {
  @Input({ required: true }) label = '';
  @Input({ required: true }) set valor(v: UsoRecurso) {
    this.uso.set(v);
  }

  uso = signal<UsoRecurso>({ usados: 0, limite: null });
  /** Sin límite: la barra muestra un tramo fijo para que no parezca vacía. */
  porcentaje = computed(() => {
    const { usados, limite } = this.uso();
    if (limite === null) return usados > 0 ? 15 : 0;
    return Math.min(100, (usados / limite) * 100);
  });
  lleno = computed(() => {
    const { usados, limite } = this.uso();
    return limite !== null && usados >= limite;
  });
}
