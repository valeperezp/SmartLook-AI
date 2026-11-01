# Diagramas de Robustez (ICONIX) — SmartLook IA

Esta carpeta contiene los modelos y diagramas de robustez correspondientes al **Capítulo III (Sección 3.2)** para el sistema **SmartLook IA**, desarrollados bajo la metodología **ICONIX** en formato estándar **XMI 2.1** para **Enterprise Architect (Sparx Systems)**.

---

## 📁 Archivos Disponibles

1. **`Paquete1_Robustez_CU01_a_CU05.xmi`**  
   Paquete completo consolidado que contiene los 5 primeros casos de uso (Paquete P1 SaaS Multitenant). Permite importar todos los diagramas y elementos de una sola vez.

2. **Archivos Individuales:**
   * **`CU01_Robustez.xmi`**: CU01 — Iniciar sesión en el contexto de una empresa
   * **`CU02_Robustez.xmi`**: CU02 — Gestionar empresas contratantes
   * **`CU03_Robustez.xmi`**: CU03 — Gestionar planes de suscripción
   * **`CU04_Robustez.xmi`**: CU04 — Gestionar suscripción de una empresa
   * **`CU05_Robustez.xmi`**: CU05 — Verificar plan y límites de la suscripción (Included)

3. **`generar_xmi.py`**  
   Script en Python para regenerar o ampliar los diagramas de robustez automáticamente.

---

## 🚀 Cómo importar en Enterprise Architect (Sparx Systems)

Sigue estos sencillos pasos para importar cualquiera de los archivos `.xmi` en tu proyecto de Enterprise Architect:

### Método Rápido:
1. Abre tu proyecto en **Enterprise Architect** (`.eap`, `.eapx` o `.qea`).
2. En el panel **Browser / Project Explorer**, haz clic derecho sobre el paquete raíz o la carpeta donde deseas cargar los diagramas (por ejemplo `Model` o `Fase de Análisis`).
3. Ve al menú contextual:
   * **Import/Export** ➔ **Import Package from XMI File...** (o presiona el atajo `Ctrl + Alt + I`).
4. En el diálogo que se abre:
   * En **Filename**, presiona **Browse...** y selecciona el archivo `.xmi` (ejemplo: `Paquete1_Robustez_CU01_a_CU05.xmi`).
   * Asegúrate de que el formato esté seleccionado en **XMI 2.1** (o automático).
   * Haz clic en el botón **Import**.
5. ¡Listo! Enterprise Architect creará el árbol de paquetes con:
   * Los actores con forma de stickman.
   * Las fronteras con el icono «boundary» (⊣○).
   * Los controles con el icono «control» (⟲).
   * Las entidades con el icono «entity» (⊚).
   * El diagrama gráfico de análisis renderizado con sus enlaces y descripciones.
