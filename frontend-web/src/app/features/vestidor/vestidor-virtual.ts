import { Component, ElementRef, OnDestroy, OnInit, ViewChild, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { IconComponent } from '../../core/components/icon/icon';
import { CatalogoService } from '../../core/services/catalogo.service';
import { Producto } from '../../core/models/catalogo.model';

type ModoVestidor = 'camara' | 'foto';

/**
 * CU05 — Vestidor virtual (AR en el navegador).
 *
 * No tenemos fotos de las prendas con fondo transparente (son fotos de catálogo
 * completas), así que en vez de superponer la foto real, dibujamos una silueta
 * de la prenda coloreada por categoría que sigue el cuerpo detectado con MediaPipe
 * Pose (corre 100% en el navegador, sin backend). Dos formas de probarse la prenda:
 * cámara en vivo, o subiendo una foto propia (una sola detección, sin loop).
 */
@Component({
  selector: 'app-vestidor-virtual',
  standalone: true,
  imports: [CommonModule, FormsModule, IconComponent],
  templateUrl: './vestidor-virtual.html',
  styleUrl: './vestidor-virtual.scss',
})
export class VestidorVirtual implements OnInit, OnDestroy {
  private catalogoService = inject(CatalogoService);

  @ViewChild('video') private videoRef?: ElementRef<HTMLVideoElement>;
  @ViewChild('imagenFoto') private imagenFotoRef?: ElementRef<HTMLImageElement>;
  @ViewChild('canvas') private canvasRef?: ElementRef<HTMLCanvasElement>;

  productos = signal<Producto[]>([]);
  productoSeleccionadoId = signal<number | null>(null);

  modo = signal<ModoVestidor>('camara');

  cargandoModelo = signal(false);
  camaraActiva = signal(false);

  fotoUrl = signal<string | null>(null);
  fotoProcesando = signal(false);
  fotoSinPersona = signal(false);
  fotoBajaConfianza = signal(false);

  error = signal<string | null>(null);

  private stream: MediaStream | null = null;
  private poseLandmarker: any = null;
  private modoLandmarkerActual: 'IMAGE' | 'VIDEO' | null = null;
  private frameId: number | null = null;
  private landmarksFotoActual: any[] | null = null;

  private readonly CATEGORIA_COLOR: Record<string, string> = {
    Camisetas: '#b3714f',
    Camisas: '#5b7a9d',
    Chaquetas: '#4a4a4a',
    Pantalones: '#3f5b48',
    Vestidos: '#8e4d6b',
  };

  // Color real dominante de cada producto, extraído de su foto (en vez del color fijo
  // por categoría). Se calcula una sola vez por producto y se cachea acá.
  private coloresProductoCache = new Map<number, string>();

  // Recorte PNG con fondo transparente de la prenda (modelo_ar_url), precargado y
  // cacheado por producto. Cuando está disponible, se dibuja la imagen real en vez
  // de la silueta vectorial — mucho más realista. Si no está (producto sin recorte
  // generado, o la imagen todavía no cargó), se cae al dibujo vectorial de siempre.
  private imagenesRecorteCache = new Map<number, HTMLImageElement>();

  productoSeleccionado(): Producto | undefined {
    return this.productos().find((p) => p.id === this.productoSeleccionadoId());
  }

  ngOnInit() {
    this.catalogoService.listarProductos(false).subscribe({
      next: (data) => {
        this.productos.set(data);
        if (data.length > 0) {
          this.productoSeleccionadoId.set(data[0].id);
          this.precalcularColorProducto(data[0]);
          this.precargarRecorteProducto(data[0]);
        }
      },
    });
  }

  ngOnDestroy() {
    this.detenerCamara();
    this.limpiarFoto();
  }

  cambiarModo(nuevo: ModoVestidor) {
    if (this.modo() === nuevo) return;
    this.detenerCamara();
    this.limpiarFoto();
    this.error.set(null);
    this.modo.set(nuevo);
  }

  onProductoChange(id: number) {
    this.productoSeleccionadoId.set(id);
    const prod = this.productoSeleccionado();
    if (prod) {
      this.precalcularColorProducto(prod);
      this.precargarRecorteProducto(prod);
    }

    // Si ya hay una foto con landmarks detectados, redibujamos con la prenda nueva
    // sin volver a correr la detección de pose (no cambió la persona en la foto).
    if (this.modo() === 'foto' && this.landmarksFotoActual) {
      this.redibujarFoto();
    }
  }

  /**
   * Calcula (una sola vez, cacheado) el color dominante de la foto real del producto,
   * muestreando el centro de la imagen — ahí es mucho más probable que esté la tela de
   * la prenda que el fondo. Si falla (sin foto, error de red, CORS), se usa el color fijo
   * por categoría como respaldo, así que nunca rompe el dibujo.
   */
  private precalcularColorProducto(prod: Producto) {
    if (!prod.imagen_url || this.coloresProductoCache.has(prod.id)) return;

    const img = new Image();
    img.crossOrigin = 'anonymous';
    img.onload = () => {
      try {
        const tmp = document.createElement('canvas');
        const tamaño = 40;
        tmp.width = tamaño;
        tmp.height = tamaño;
        const tctx = tmp.getContext('2d');
        if (!tctx) return;

        const cx = img.naturalWidth * 0.3;
        const cy = img.naturalHeight * 0.22;
        const cw = img.naturalWidth * 0.4;
        const ch = img.naturalHeight * 0.45;
        tctx.drawImage(img, cx, cy, cw, ch, 0, 0, tamaño, tamaño);

        const data = tctx.getImageData(0, 0, tamaño, tamaño).data;
        let r = 0, g = 0, b = 0, n = 0;
        for (let i = 0; i < data.length; i += 4) {
          r += data[i];
          g += data[i + 1];
          b += data[i + 2];
          n++;
        }
        const color = `rgb(${Math.round(r / n)}, ${Math.round(g / n)}, ${Math.round(b / n)})`;
        this.coloresProductoCache.set(prod.id, color);

        // Si estamos viendo esta misma foto ahora, redibujamos con el color ya real.
        if (this.modo() === 'foto' && this.landmarksFotoActual && this.productoSeleccionadoId() === prod.id) {
          this.redibujarFoto();
        }
      } catch {
        // Canvas "contaminado" por CORS u otro error: nos quedamos con el color de categoría.
      }
    };
    img.onerror = () => {};
    img.src = prod.imagen_url;
  }

  /** Precarga (una sola vez, cacheado) el recorte PNG transparente de la prenda, si existe. */
  private precargarRecorteProducto(prod: Producto) {
    if (!prod.modelo_ar_url || this.imagenesRecorteCache.has(prod.id)) return;

    const img = new Image();
    img.crossOrigin = 'anonymous';
    img.onload = () => {
      this.imagenesRecorteCache.set(prod.id, img);
      if (this.modo() === 'foto' && this.landmarksFotoActual && this.productoSeleccionadoId() === prod.id) {
        this.redibujarFoto();
      }
    };
    img.onerror = () => {};
    img.src = prod.modelo_ar_url;
  }

  private colorParaDibujar(prod: Producto | undefined, categoria: string): string {
    if (prod && this.coloresProductoCache.has(prod.id)) {
      return this.coloresProductoCache.get(prod.id)!;
    }
    return this.CATEGORIA_COLOR[categoria] || '#b3714f';
  }

  /** Aclara/oscurece un color "rgb(r, g, b)" o "#rrggbb" — usado para el sombreado de tela. */
  private ajustarLuminosidad(color: string, delta: number): string {
    let r: number, g: number, b: number;
    const rgbMatch = color.match(/rgb\((\d+),\s*(\d+),\s*(\d+)\)/);
    if (rgbMatch) {
      [r, g, b] = [+rgbMatch[1], +rgbMatch[2], +rgbMatch[3]];
    } else {
      const hex = color.replace('#', '');
      r = parseInt(hex.substring(0, 2), 16);
      g = parseInt(hex.substring(2, 4), 16);
      b = parseInt(hex.substring(4, 6), 16);
    }
    const ajustar = (v: number) => Math.max(0, Math.min(255, Math.round(v + delta)));
    return `rgb(${ajustar(r)}, ${ajustar(g)}, ${ajustar(b)})`;
  }

  // ---------------------------------------------------------------------
  // Modo cámara
  // ---------------------------------------------------------------------

  async iniciarCamara() {
    this.error.set(null);
    this.cargandoModelo.set(true);

    try {
      this.stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: 'user', width: 640, height: 480 },
      });
    } catch {
      this.error.set(
        'No pudimos acceder a tu cámara. Revisá los permisos del navegador para este sitio e intentá de nuevo.'
      );
      this.cargandoModelo.set(false);
      return;
    }

    const video = this.videoRef?.nativeElement;
    if (!video) return;
    video.srcObject = this.stream;
    await video.play();

    try {
      await this.asegurarModeloPose('VIDEO');
    } catch {
      this.error.set(
        'No se pudo cargar el modelo de detección de pose (revisá tu conexión a internet). Podés seguir viendo la cámara, pero sin la silueta de la prenda.'
      );
    }

    this.cargandoModelo.set(false);
    this.camaraActiva.set(true);
    this.loopDeteccion();
  }

  detenerCamara() {
    if (this.frameId !== null) {
      cancelAnimationFrame(this.frameId);
      this.frameId = null;
    }
    this.stream?.getTracks().forEach((track) => track.stop());
    this.stream = null;
    this.camaraActiva.set(false);
  }

  private loopDeteccion = () => {
    if (!this.camaraActiva()) return;

    const video = this.videoRef?.nativeElement;
    const canvas = this.canvasRef?.nativeElement;
    if (video && canvas && video.readyState >= 2) {
      canvas.width = video.videoWidth;
      canvas.height = video.videoHeight;
      const ctx = canvas.getContext('2d');

      if (ctx && this.poseLandmarker) {
        const resultado = this.poseLandmarker.detectForVideo(video, performance.now());
        ctx.clearRect(0, 0, canvas.width, canvas.height);
        const landmarks = resultado?.landmarks?.[0];
        if (landmarks) {
          this.dibujarPrenda(ctx, landmarks, canvas.width, canvas.height);
        }
      }
    }

    this.frameId = requestAnimationFrame(this.loopDeteccion);
  };

  // ---------------------------------------------------------------------
  // Modo foto (subir una imagen propia)
  // ---------------------------------------------------------------------

  async onFotoSeleccionada(event: Event) {
    const input = event.target as HTMLInputElement;
    const archivo = input.files?.[0];
    if (!archivo) return;

    this.limpiarFoto();
    this.error.set(null);
    this.fotoSinPersona.set(false);
    this.fotoBajaConfianza.set(false);
    this.fotoProcesando.set(true);
    this.fotoUrl.set(URL.createObjectURL(archivo));

    // Esperamos al próximo ciclo para que el <img> del template exista con el src ya seteado.
    setTimeout(() => this.procesarFotoCargada(), 0);
  }

  private async procesarFotoCargada() {
    const img = this.imagenFotoRef?.nativeElement;
    if (!img) {
      this.fotoProcesando.set(false);
      return;
    }

    if (!img.complete) {
      await new Promise<void>((resolve) => {
        img.onload = () => resolve();
        img.onerror = () => resolve();
      });
    }

    try {
      await this.asegurarModeloPose('IMAGE');
    } catch {
      this.error.set('No se pudo cargar el modelo de detección de pose (revisá tu conexión a internet).');
      this.fotoProcesando.set(false);
      return;
    }

    const canvas = this.canvasRef?.nativeElement;
    if (!canvas || !this.poseLandmarker) {
      this.fotoProcesando.set(false);
      return;
    }

    canvas.width = img.naturalWidth;
    canvas.height = img.naturalHeight;

    const resultado = this.poseLandmarker.detect(img);
    const landmarks = resultado?.landmarks?.[0] ?? null;
    this.landmarksFotoActual = landmarks;

    if (!landmarks) {
      this.fotoSinPersona.set(true);
    } else {
      this.redibujarFoto();
    }

    this.fotoProcesando.set(false);
  }

  private redibujarFoto() {
    const canvas = this.canvasRef?.nativeElement;
    const ctx = canvas?.getContext('2d');
    if (!canvas || !ctx || !this.landmarksFotoActual) return;

    ctx.clearRect(0, 0, canvas.width, canvas.height);
    const ok = this.dibujarPrenda(ctx, this.landmarksFotoActual, canvas.width, canvas.height);
    this.fotoBajaConfianza.set(!ok);
  }

  limpiarFoto() {
    const url = this.fotoUrl();
    if (url) URL.revokeObjectURL(url);
    this.fotoUrl.set(null);
    this.fotoSinPersona.set(false);
    this.fotoBajaConfianza.set(false);
    this.fotoProcesando.set(false);
    this.landmarksFotoActual = null;

    const canvas = this.canvasRef?.nativeElement;
    canvas?.getContext('2d')?.clearRect(0, 0, canvas.width, canvas.height);
  }

  // ---------------------------------------------------------------------
  // Compartido: modelo de pose + dibujo de la prenda
  // ---------------------------------------------------------------------

  private async asegurarModeloPose(runningMode: 'IMAGE' | 'VIDEO') {
    if (!this.poseLandmarker) {
      // Import dinámico desde CDN. Se arma la URL en una variable (no como string literal
      // en el import) para que TypeScript no intente resolver el módulo en tiempo de build.
      const cdnUrl = 'https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.14/+esm';
      const vision: any = await import(/* @vite-ignore */ cdnUrl);
      const { PoseLandmarker, FilesetResolver } = vision;

      const filesetResolver = await FilesetResolver.forVisionTasks(
        'https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.14/wasm'
      );

      this.poseLandmarker = await PoseLandmarker.createFromOptions(filesetResolver, {
        baseOptions: {
          modelAssetPath:
            'https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_lite/float16/latest/pose_landmarker_lite.task',
          delegate: 'GPU',
        },
        runningMode,
        numPoses: 1,
      });
      this.modoLandmarkerActual = runningMode;
      return;
    }

    if (this.modoLandmarkerActual !== runningMode) {
      await this.poseLandmarker.setOptions({ runningMode });
      this.modoLandmarkerActual = runningMode;
    }
  }

  /**
   * Dibuja la silueta de la prenda sobre el cuerpo detectado. Devuelve `false` cuando los
   * puntos clave necesarios no se detectaron con confianza suficiente (ej. una foto tipo
   * retrato donde no se ve la cadera) — en ese caso no dibuja nada en vez de mostrar una
   * forma deformada, y el llamador puede avisarle al usuario.
   */
  private dibujarPrenda(ctx: CanvasRenderingContext2D, landmarks: any[], w: number, h: number): boolean {
    const prod = this.productoSeleccionado();
    const categoria = prod?.categoria?.nombre || 'Camisetas';
    const color = this.colorParaDibujar(prod, categoria);

    const pto = (i: number) => ({
      x: landmarks[i].x * w,
      y: landmarks[i].y * h,
      vis: landmarks[i].visibility ?? 1,
    });
    const hombroI = pto(11);
    const hombroD = pto(12);

    const anchoHombros = Math.abs(hombroD.x - hombroI.x);
    const hombrosConfiables =
      anchoHombros > w * 0.03 && hombroI.vis > 0.4 && hombroD.vis > 0.4;
    if (!hombrosConfiables) return false;

    if (categoria === 'Pantalones') {
      const caderaI = pto(23);
      const caderaD = pto(24);
      const rodillaI = pto(25);
      const rodillaD = pto(26);
      // No alcanza con visibility>0.4 y "está más abajo que...": cuando la rodilla no
      // entra en la foto, MediaPipe puede "inventar" una posición cercana al hombro con
      // una confianza que igual pasa ese filtro, y el pantalón termina dibujado sobre el
      // pecho. Exigimos que la separación vertical hombro→cadera→rodilla sea proporcional
      // al ancho de hombros (proporciones de un cuerpo real), no solo "algo más abajo".
      const caderaValida =
        caderaI.vis > 0.4 &&
        caderaD.vis > 0.4 &&
        caderaI.y - hombroI.y > anchoHombros * 0.6 &&
        caderaD.y - hombroD.y > anchoHombros * 0.6;
      const rodillaValida =
        rodillaI.vis > 0.4 &&
        rodillaD.vis > 0.4 &&
        rodillaI.y - caderaI.y > anchoHombros * 0.5 &&
        rodillaD.y - caderaD.y > anchoHombros * 0.5;
      if (!caderaValida || !rodillaValida) return false;

      const centroCaderaX = (caderaI.x + caderaD.x) / 2;
      const entrepierna = { x: centroCaderaX, y: Math.min(caderaI.y, caderaD.y) + Math.abs(caderaD.x - caderaI.x) * 0.55 };

      const imgPantalon = prod ? this.imagenesRecorteCache.get(prod.id) : undefined;
      if (imgPantalon && imgPantalon.naturalWidth > 0) {
        // Recorte real con transparencia: se dibuja la foto de la prenda, escalada a
        // cadera+piernas, en vez de rellenar un path vectorial con color plano.
        const anchoCadera = Math.abs(caderaD.x - caderaI.x) + anchoHombros * 0.15;
        const largoPiernas = Math.max(rodillaI.y, rodillaD.y) - Math.min(caderaI.y, caderaD.y);
        const drawHeight = largoPiernas * 2.1;
        const drawWidth = drawHeight * (imgPantalon.naturalWidth / imgPantalon.naturalHeight);
        const anchoFinal = Math.max(drawWidth, anchoCadera * 1.3);
        const altoFinal = anchoFinal * (imgPantalon.naturalHeight / imgPantalon.naturalWidth);
        ctx.save();
        ctx.globalAlpha = 0.97;
        ctx.drawImage(
          imgPantalon,
          centroCaderaX - anchoFinal / 2,
          Math.min(caderaI.y, caderaD.y) - altoFinal * 0.06,
          anchoFinal,
          altoFinal
        );
        ctx.restore();
      } else {
        ctx.save();
        ctx.globalAlpha = 0.62;
        const gradPantalon = ctx.createLinearGradient(caderaI.x, caderaI.y, rodillaD.x, rodillaD.y);
        gradPantalon.addColorStop(0, this.ajustarLuminosidad(color, 18));
        gradPantalon.addColorStop(1, this.ajustarLuminosidad(color, -22));
        ctx.fillStyle = gradPantalon;

        // Pierna izquierda
        ctx.beginPath();
        ctx.moveTo(caderaI.x, caderaI.y);
        ctx.lineTo(entrepierna.x, entrepierna.y);
        ctx.lineTo((entrepierna.x + rodillaI.x) / 2, rodillaI.y);
        ctx.lineTo(rodillaI.x - anchoHombros * 0.06, rodillaI.y);
        ctx.lineTo(caderaI.x - anchoHombros * 0.04, caderaI.y);
        ctx.closePath();
        ctx.fill();

        // Pierna derecha
        ctx.beginPath();
        ctx.moveTo(caderaD.x, caderaD.y);
        ctx.lineTo(entrepierna.x, entrepierna.y);
        ctx.lineTo((entrepierna.x + rodillaD.x) / 2, rodillaD.y);
        ctx.lineTo(rodillaD.x + anchoHombros * 0.06, rodillaD.y);
        ctx.lineTo(caderaD.x + anchoHombros * 0.04, caderaD.y);
        ctx.closePath();
        ctx.fill();

        // Línea de cintura
        ctx.globalAlpha = 0.75;
        ctx.strokeStyle = this.ajustarLuminosidad(color, -30);
        ctx.lineWidth = Math.max(2, anchoHombros * 0.025);
        ctx.beginPath();
        ctx.moveTo(caderaI.x - anchoHombros * 0.04, caderaI.y);
        ctx.lineTo(caderaD.x + anchoHombros * 0.04, caderaD.y);
        ctx.stroke();
        ctx.restore();
      }
    } else {
      // Prenda de torso: alto proporcional al ancho de hombros (no a la cadera, que en
      // fotos tipo retrato no se ve y el modelo la "inventa" con muy baja confianza).
      // Categorías con manga larga y prendas más largas (vestidos) se diferencian por
      // el largo de manga y el alto total, no solo el color.
      const esMangaLarga = categoria === 'Camisas' || categoria === 'Chaquetas';
      const esVestido = categoria === 'Vestidos';

      const centroX = (hombroI.x + hombroD.x) / 2;
      const yArriba = Math.max(hombroI.y, hombroD.y) + anchoHombros * 0.04;
      const altoTorso = anchoHombros * (esVestido ? 2.3 : 1.3);
      const yAbajo = Math.min(yArriba + altoTorso, h - 2);
      const anchoLateral = anchoHombros * (esVestido ? 0.5 : 0.44);

      const cuelloAncho = anchoHombros * 0.2;
      const cuelloProfundo = anchoHombros * (esMangaLarga ? 0.1 : 0.14);
      const mangaCaida = anchoHombros * (esMangaLarga ? 0.42 : 0.2);
      const mangaAfuera = anchoHombros * (esMangaLarga ? 0.16 : 0.22);
      const axilaInset = anchoHombros * 0.06;
      const axilaY = yArriba + anchoHombros * 0.32;

      const imgTorso = prod ? this.imagenesRecorteCache.get(prod.id) : undefined;
      if (imgTorso && imgTorso.naturalWidth > 0) {
        // Recorte real con transparencia: se dibuja la foto de la prenda, escalada al
        // ancho de hombros+mangas, en vez de rellenar un path vectorial con color plano.
        const anchoFinal = anchoHombros * (esVestido ? 2.3 : 2.6);
        const altoFinal = anchoFinal * (imgTorso.naturalHeight / imgTorso.naturalWidth);
        ctx.save();
        ctx.globalAlpha = 0.97;
        ctx.drawImage(imgTorso, centroX - anchoFinal / 2, yArriba - altoFinal * 0.07, anchoFinal, altoFinal);
        ctx.restore();
      } else {
        ctx.save();
        ctx.globalAlpha = 0.62;
        const grad = ctx.createLinearGradient(hombroI.x, yArriba, hombroD.x, yAbajo);
        grad.addColorStop(0, this.ajustarLuminosidad(color, 22));
        grad.addColorStop(0.5, color);
        grad.addColorStop(1, this.ajustarLuminosidad(color, -25));
        ctx.fillStyle = grad;

        ctx.beginPath();
        // Cuello izquierdo -> hombro izquierdo
        ctx.moveTo(centroX - cuelloAncho, yArriba);
        ctx.lineTo(hombroI.x, yArriba);
        // Manga izquierda
        ctx.lineTo(hombroI.x - mangaAfuera, yArriba + mangaCaida);
        ctx.lineTo(hombroI.x - axilaInset, axilaY);
        // Lateral izquierdo hasta el ruedo
        ctx.lineTo(centroX - anchoLateral, yAbajo);
        // Ruedo
        ctx.lineTo(centroX + anchoLateral, yAbajo);
        // Lateral derecho hasta la axila
        ctx.lineTo(hombroD.x + axilaInset, axilaY);
        // Manga derecha
        ctx.lineTo(hombroD.x + mangaAfuera, yArriba + mangaCaida);
        ctx.lineTo(hombroD.x, yArriba);
        // Escote (curva)
        ctx.lineTo(centroX + cuelloAncho, yArriba);
        ctx.quadraticCurveTo(centroX, yArriba + cuelloProfundo, centroX - cuelloAncho, yArriba);
        ctx.closePath();
        ctx.fill();

        // Línea de costura central sutil, para que no se vea tan plano.
        ctx.globalAlpha = 0.25;
        ctx.strokeStyle = this.ajustarLuminosidad(color, -40);
        ctx.lineWidth = Math.max(1, anchoHombros * 0.012);
        ctx.beginPath();
        ctx.moveTo(centroX, yArriba + cuelloProfundo * 1.3);
        ctx.lineTo(centroX, yAbajo);
        ctx.stroke();
        ctx.restore();
      }
    }

    // Etiqueta con el nombre de la prenda, arriba de los hombros.
    if (prod) {
      const centroX = (hombroI.x + hombroD.x) / 2;
      const topY = Math.max(Math.min(hombroI.y, hombroD.y) - 14, 18);
      const tamañoFuente = Math.max(14, Math.min(20, anchoHombros * 0.14));
      ctx.save();
      ctx.font = `600 ${tamañoFuente}px sans-serif`;
      ctx.textAlign = 'center';
      ctx.fillStyle = '#fff';
      ctx.strokeStyle = 'rgba(0,0,0,0.6)';
      ctx.lineWidth = 3;
      ctx.strokeText(prod.nombre, centroX, topY);
      ctx.fillText(prod.nombre, centroX, topY);
      ctx.restore();
    }

    return true;
  }
}
