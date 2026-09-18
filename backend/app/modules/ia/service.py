"""Lógica de negocio del módulo ia (CU20 — analizar preferencias, CU06 — generar recomendaciones).

Motor basado en reglas: analiza el historial de reservas del cliente (categoría,
temporada, colección de los productos que reservó) y puntúa el catálogo activo
según esas coincidencias. Si el cliente no tiene historial, recomienda lo más
popular entre todos los clientes. Pensado para poder swappearse más adelante por
una llamada a un LLM externo sin tocar el router (ver `ai_api_key` en config).
"""
import unicodedata
from collections import Counter

import httpx
from sqlalchemy import func, or_
from sqlalchemy.orm import Session, joinedload

from app.modules.catalogo.models import Categoria, Coleccion, Producto, Temporada
from app.modules.ia.models import ConfiguracionIA
from app.modules.inventario.models import Inventario
from app.modules.reservas.models import Reserva, ReservaItem
from app.modules.sucursales.models import Sucursal
from app.shared.core.config import settings


def _historial_cliente(db: Session, cliente_id: int) -> list[ReservaItem]:
    """Items reservados por el cliente (incluye canceladas: igual reflejan interés)."""
    return (
        db.query(ReservaItem)
        .join(Reserva, Reserva.id == ReservaItem.reserva_id)
        .options(joinedload(ReservaItem.producto))
        .filter(Reserva.cliente_id == cliente_id)
        .all()
    )


def analizar_preferencias(db: Session, cliente_id: int) -> dict:
    """CU20: deriva el perfil de preferencias del cliente a partir de su historial de reservas."""
    historial = _historial_cliente(db, cliente_id)

    if not historial:
        return {"tiene_historial": False, "total_reservas_analizadas": 0, "preferencias": []}

    categoria_peso: Counter = Counter()
    temporada_peso: Counter = Counter()
    coleccion_peso: Counter = Counter()

    for item in historial:
        producto = item.producto
        if not producto:
            continue
        if producto.categoria_id:
            categoria_peso[producto.categoria_id] += item.cantidad
        if producto.temporada_id:
            temporada_peso[producto.temporada_id] += item.cantidad
        if producto.coleccion_id:
            coleccion_peso[producto.coleccion_id] += item.cantidad

    preferencias = []
    for categoria_id, peso in categoria_peso.most_common(3):
        nombre = db.query(Categoria.nombre).filter(Categoria.id == categoria_id).scalar()
        if nombre:
            preferencias.append({"tipo": "categoria", "nombre": nombre, "peso": peso})
    for temporada_id, peso in temporada_peso.most_common(2):
        nombre = db.query(Temporada.nombre).filter(Temporada.id == temporada_id).scalar()
        if nombre:
            preferencias.append({"tipo": "temporada", "nombre": nombre, "peso": peso})
    for coleccion_id, peso in coleccion_peso.most_common(2):
        nombre = db.query(Coleccion.nombre).filter(Coleccion.id == coleccion_id).scalar()
        if nombre:
            preferencias.append({"tipo": "coleccion", "nombre": nombre, "peso": peso})

    preferencias.sort(key=lambda p: p["peso"], reverse=True)

    return {
        "tiene_historial": True,
        "total_reservas_analizadas": len(historial),
        "preferencias": preferencias,
    }


def _popularidad_global(db: Session) -> Counter:
    """Cantidad de unidades reservadas por producto, en todos los clientes (para desempate/fallback)."""
    filas = (
        db.query(ReservaItem.producto_id, func.coalesce(func.sum(ReservaItem.cantidad), 0))
        .join(Reserva, Reserva.id == ReservaItem.reserva_id)
        .filter(Reserva.estado != "cancelada")
        .group_by(ReservaItem.producto_id)
        .all()
    )
    return Counter({producto_id: int(total) for producto_id, total in filas})


def generar_recomendaciones(db: Session, cliente_id: int, limit: int = 8) -> list[dict]:
    """CU06: genera hasta `limit` recomendaciones de productos para el cliente."""
    historial = _historial_cliente(db, cliente_id)

    categoria_peso: Counter = Counter()
    temporada_peso: Counter = Counter()
    coleccion_peso: Counter = Counter()
    ya_reservados: set[int] = set()

    for item in historial:
        producto = item.producto
        if not producto:
            continue
        ya_reservados.add(producto.id)
        if producto.categoria_id:
            categoria_peso[producto.categoria_id] += item.cantidad
        if producto.temporada_id:
            temporada_peso[producto.temporada_id] += item.cantidad
        if producto.coleccion_id:
            coleccion_peso[producto.coleccion_id] += item.cantidad

    # Solo se recomiendan productos activos con stock disponible en alguna sucursal.
    productos_con_stock = {
        pid
        for (pid,) in db.query(Inventario.producto_id)
        .filter(Inventario.activo.is_(True), Inventario.cantidad_disponible > 0)
        .distinct()
        .all()
    }

    candidatos = (
        db.query(Producto)
        .options(joinedload(Producto.categoria))
        .filter(Producto.activo.is_(True), Producto.id.in_(productos_con_stock))
        .all()
    ) if productos_con_stock else []

    popularidad = _popularidad_global(db)

    resultados = []
    for producto in candidatos:
        if producto.id in ya_reservados:
            continue

        puntaje = 0
        motivo = None
        if producto.categoria_id in categoria_peso:
            puntaje += categoria_peso[producto.categoria_id] * 3
            motivo = f"Porque sueles reservar productos de {producto.categoria.nombre}" if producto.categoria else None
        if producto.temporada_id in temporada_peso:
            puntaje += temporada_peso[producto.temporada_id] * 2
            motivo = motivo or "Va con la temporada de tus reservas anteriores"
        if producto.coleccion_id in coleccion_peso:
            puntaje += coleccion_peso[producto.coleccion_id] * 2
            motivo = motivo or "De una colección que ya reservaste antes"

        # Pequeño empuje por popularidad general (no domina el puntaje de afinidad personal).
        puntaje += min(popularidad.get(producto.id, 0), 5)

        if not motivo:
            motivo = "Producto popular entre otros clientes"

        resultados.append({
            "producto_id": producto.id,
            "nombre_producto": producto.nombre,
            "precio": float(producto.precio),
            "nombre_categoria": producto.categoria.nombre if producto.categoria else None,
            "modelo_ar_url": producto.modelo_ar_url,
            "imagen_url": producto.imagen_url,
            "motivo": motivo,
            "puntaje": puntaje,
        })

    resultados.sort(key=lambda r: r["puntaje"], reverse=True)
    return resultados[:limit]


# =========================================================================
# CU21 — Chatbot / asistente virtual (motor de reglas por palabras clave)
# =========================================================================

_STOPWORDS = {
    "el", "la", "los", "las", "un", "una", "unos", "unas", "de", "del", "que",
    "para", "por", "con", "en", "es", "y", "o", "me", "mi", "mis", "tu", "tus",
    "se", "su", "sus", "hay", "tienen", "tiene", "quiero", "busco", "necesito",
    "como", "cual", "cuales", "donde", "porfa", "porfavor", "gracias", "hola",
    "buenas", "algo", "alguna", "algun", "info", "informacion", "ver", "dame",
}

_SALUDOS = ["hola", "buenas", "buen dia", "buenos dias", "buenas tardes", "buenas noches", "hey", "que tal"]
_AGRADECIMIENTOS = ["gracias", "muchas gracias", "genial gracias", "perfecto gracias"]
_AYUDA = ["ayuda", "que puedes hacer", "que podes hacer", "opciones", "que haces"]
_RECOMENDACION = ["recomend", "sugerime", "sugerencia", "que me aconsejas", "aconsejame"]
_RESERVAS = ["mi reserva", "mis reservas", "estado de mi reserva", "mi pedido", "mis pedidos", "reserve"]
_SUCURSALES = ["sucursal", "direccion", "donde estan", "donde queda", "donde quedan", "horario", "ubicacion"]

SUGERENCIAS_DEFAULT = [
    "¿Qué me recomendás?",
    "¿Cuáles son mis reservas?",
    "¿Dónde están las sucursales?",
    "Busco una camisa",
]


def _normalizar(texto: str) -> str:
    sin_acentos = unicodedata.normalize("NFKD", texto).encode("ascii", "ignore").decode("ascii")
    return sin_acentos.lower().strip()


def _detectar_intencion(texto_norm: str) -> str:
    if any(p in texto_norm for p in _SALUDOS):
        return "saludo"
    if any(p in texto_norm for p in _AGRADECIMIENTOS):
        return "agradecimiento"
    if any(p in texto_norm for p in _AYUDA):
        return "ayuda"
    if any(p in texto_norm for p in _RECOMENDACION):
        return "recomendacion"
    if any(p in texto_norm for p in _RESERVAS):
        return "reservas"
    if any(p in texto_norm for p in _SUCURSALES):
        return "sucursales"
    return "producto"


def _extraer_palabras_clave(texto_norm: str) -> list[str]:
    palabras = [p.strip(".,;!?¿¡") for p in texto_norm.split()]
    return [p for p in palabras if len(p) >= 4 and p not in _STOPWORDS]


def _responder_saludo() -> dict:
    return {
        "respuesta": "¡Hola! Soy el asistente virtual de SmartLook-AI. Puedo ayudarte a buscar prendas, "
                     "darte recomendaciones, contarte sobre tus reservas o las sucursales. ¿En qué te ayudo?",
        "intencion": "saludo",
        "sugerencias": SUGERENCIAS_DEFAULT,
    }


def _responder_agradecimiento() -> dict:
    return {
        "respuesta": "¡De nada! ¿Te ayudo con algo más?",
        "intencion": "agradecimiento",
        "sugerencias": SUGERENCIAS_DEFAULT,
    }


def _responder_ayuda() -> dict:
    return {
        "respuesta": "Puedo ayudarte con esto:\n"
                     "• Buscar prendas del catálogo (ej: \"busco una camisa\")\n"
                     "• Recomendarte productos según tus gustos (ej: \"qué me recomendás\")\n"
                     "• Contarte el estado de tus reservas (ej: \"cuáles son mis reservas\")\n"
                     "• Darte las direcciones de las sucursales (ej: \"dónde están las sucursales\")",
        "intencion": "ayuda",
        "sugerencias": SUGERENCIAS_DEFAULT,
    }


def _categoria_mencionada(db: Session, texto_norm: str) -> Categoria | None:
    """Si el mensaje nombra una categoría del catálogo (ej. "vestido", "vestidos"), la devuelve."""
    categorias = db.query(Categoria).filter(Categoria.activo.is_(True)).all()
    for categoria in categorias:
        nombre_norm = _normalizar(categoria.nombre)
        singular = nombre_norm[:-1] if nombre_norm.endswith("s") else nombre_norm
        if nombre_norm in texto_norm or singular in texto_norm:
            return categoria
    return None


def _responder_recomendacion(db: Session, cliente_id: int, texto_norm: str) -> dict:
    # Si el cliente pidió algo puntual (ej. "recomendame un vestido de gala"), priorizamos
    # productos reales de esa categoría por sobre el historial genérico — sino la recomendación
    # basada solo en compras pasadas puede ignorar por completo lo que el cliente pidió ahora.
    categoria = _categoria_mencionada(db, texto_norm)
    if categoria:
        productos_categoria = (
            db.query(Producto)
            .filter(Producto.activo.is_(True), Producto.categoria_id == categoria.id)
            .order_by(Producto.nombre)
            .limit(4)
            .all()
        )
        if productos_categoria:
            lineas = [f"• {p.nombre} (${float(p.precio):.2f})" for p in productos_categoria]
            return {
                "respuesta": f"Esto tenemos en {categoria.nombre}:\n" + "\n".join(lineas),
                "intencion": "recomendacion",
                "sugerencias": ["¿Cuáles son mis reservas?", "¿Dónde están las sucursales?"],
            }

    recomendaciones = generar_recomendaciones(db, cliente_id, limit=3)
    if not recomendaciones:
        return {
            "respuesta": "Por ahora no tengo suficientes productos activos para recomendarte algo. "
                         "¡Explorá el catálogo mientras tanto!",
            "intencion": "recomendacion",
            "sugerencias": SUGERENCIAS_DEFAULT,
        }
    lineas = [f"• {r['nombre_producto']} (${r['precio']:.2f}) — {r['motivo']}" for r in recomendaciones]
    return {
        "respuesta": "Basándome en tus gustos, te recomiendo:\n" + "\n".join(lineas),
        "intencion": "recomendacion",
        "sugerencias": ["Buscar otra prenda", "¿Cuáles son mis reservas?"],
    }


def _responder_reservas(db: Session, cliente_id: int) -> dict:
    reservas = (
        db.query(Reserva)
        .filter(Reserva.cliente_id == cliente_id)
        .order_by(Reserva.creada_en.desc())
        .limit(3)
        .all()
    )
    if not reservas:
        return {
            "respuesta": "Todavía no tenés reservas registradas. ¿Querés que te recomiende algo para empezar?",
            "intencion": "reservas",
            "sugerencias": ["¿Qué me recomendás?", "Busco una prenda"],
        }
    lineas = [f"• Reserva #{r.id} — {r.estado} ({r.nombre_sucursal or 'sucursal no asignada'})" for r in reservas]
    return {
        "respuesta": f"Tenés {len(reservas)} reserva(s) reciente(s):\n" + "\n".join(lineas),
        "intencion": "reservas",
        "sugerencias": ["¿Qué me recomendás?", "¿Dónde están las sucursales?"],
    }


def _responder_sucursales(db: Session) -> dict:
    sucursales = db.query(Sucursal).filter(Sucursal.activa.is_(True)).order_by(Sucursal.nombre).all()
    if not sucursales:
        return {
            "respuesta": "No encontré sucursales activas registradas por el momento.",
            "intencion": "sucursales",
            "sugerencias": SUGERENCIAS_DEFAULT,
        }
    lineas = [f"• {s.nombre} — {s.direccion}" + (f", {s.ciudad}" if s.ciudad else "") for s in sucursales]
    return {
        "respuesta": "Estas son nuestras sucursales:\n" + "\n".join(lineas),
        "intencion": "sucursales",
        "sugerencias": ["¿Qué me recomendás?", "Busco una prenda"],
    }


# Palabras genéricas ("ropa en general") o de seguimiento ("dame más detalles") — no tiene
# sentido buscarlas literalmente contra nombre/categoría. Sirven como red de seguridad para
# el texto de respaldo por reglas; cuando el proveedor de IA está disponible, el historial de
# la conversación + el catálogo completo (ver `_resumen_catalogo_completo`) le dan contexto
# real para responder estos casos con precisión.
_TERMINOS_GENERICOS = {
    "ropa", "prenda", "prendas", "producto", "productos", "catalogo",
    "articulo", "articulos", "cosas", "vestimenta", "indumentaria",
    "detalle", "detalles", "informacion", "info",
}


def _productos_populares(db: Session, limit: int = 5) -> list[Producto]:
    popularidad = _popularidad_global(db)
    if not popularidad:
        return (
            db.query(Producto)
            .filter(Producto.activo.is_(True))
            .limit(limit)
            .all()
        )
    ids_ordenados = [pid for pid, _ in popularidad.most_common(limit)]
    productos = (
        db.query(Producto)
        .options(joinedload(Producto.categoria))
        .filter(Producto.id.in_(ids_ordenados), Producto.activo.is_(True))
        .all()
    )
    por_id = {p.id: p for p in productos}
    return [por_id[pid] for pid in ids_ordenados if pid in por_id]


def _responder_producto(db: Session, texto_norm: str) -> dict:
    palabras = _extraer_palabras_clave(texto_norm)
    palabras_busqueda = [p for p in palabras if p not in _TERMINOS_GENERICOS]

    if not palabras or not palabras_busqueda:
        # No dijo nada buscable (o solo dijo algo genérico como "ropa"/"catálogo"):
        # mostramos lo más popular en vez de un callejón sin salida.
        populares = _productos_populares(db)
        if not populares:
            return {
                "respuesta": "Todavía no tengo productos activos para mostrarte. ¡Volvé a intentar más tarde!",
                "intencion": "producto",
                "sugerencias": SUGERENCIAS_DEFAULT,
            }
        lineas = [f"• {p.nombre} ({p.categoria.nombre}) — ${float(p.precio):.2f}" for p in populares]
        return {
            "respuesta": "Esto es lo más popular en nuestro catálogo ahora mismo:\n" + "\n".join(lineas),
            "intencion": "producto",
            "sugerencias": ["¿Qué me recomendás?", "¿Cuáles son mis reservas?"],
        }

    condiciones = []
    for palabra in palabras_busqueda:
        patron = f"%{palabra}%"
        condiciones.append(Producto.nombre.ilike(patron))
        condiciones.append(Producto.descripcion.ilike(patron))
        condiciones.append(Categoria.nombre.ilike(patron))

    resultados = (
        db.query(Producto)
        .join(Categoria, Categoria.id == Producto.categoria_id)
        .filter(Producto.activo.is_(True), or_(*condiciones))
        .limit(5)
        .all()
    )

    if not resultados:
        populares = _productos_populares(db)
        lineas = [f"• {p.nombre} ({p.categoria.nombre}) — ${float(p.precio):.2f}" for p in populares]
        extra = ("\n\nEsto es lo más popular en su lugar:\n" + "\n".join(lineas)) if populares else ""
        return {
            "respuesta": f"No encontré prendas relacionadas con \"{' '.join(palabras_busqueda)}\" en el catálogo activo.{extra}",
            "intencion": "producto",
            "sugerencias": ["¿Qué me recomendás?", "¿Dónde están las sucursales?"],
        }

    lineas = [f"• {p.nombre} ({p.categoria.nombre}) — ${float(p.precio):.2f}" for p in resultados]
    return {
        "respuesta": "Encontré estas prendas que podrían interesarte:\n" + "\n".join(lineas),
        "intencion": "producto",
        "sugerencias": ["¿Qué me recomendás?", "¿Cuáles son mis reservas?"],
    }


_SYSTEM_PROMPT_CHAT = (
    "Sos el asistente virtual de SmartLook-AI, una tienda de ropa con sucursales físicas. "
    "Respondé siempre en español, en un tono cordial, natural y breve (máximo 4-5 líneas), como un mensaje de chat. "
    "Usá EXCLUSIVAMENTE datos reales: los que aparecen en 'Datos disponibles' de este turno, o los que vos mismo "
    "ya mencionaste antes en esta misma conversación — nunca inventes productos, precios, reservas ni sucursales "
    "nuevas. Conservá los números y nombres exactamente como aparecen. "
    "Si el cliente pide más detalles o amplía sobre algo que ya se mencionó antes (ej: \"dame más detalles\", "
    "\"contame más de ese\", \"el segundo\"), usá el historial de la conversación para identificar de qué producto "
    "habla y respondé con lo que ya sabés de él (categoría, precio, descripción) sin inventar características "
    "que no estén en los datos que tenés. "
    "Si 'Datos disponibles' está vacío y no hay nada relevante en la conversación previa, decilo con honestidad "
    "en vez de inventar una respuesta."
)


# =========================================================================
# Configuración del proveedor de IA (admin) — estándar API de OpenAI
# (base_url + api_key + modelo), compatible con Ollama, OpenAI, Groq, etc.
# =========================================================================

_CONFIG_ID = 1


def obtener_configuracion_ia(db: Session) -> ConfiguracionIA:
    """Devuelve la fila única de configuración, creándola con los valores por defecto si no existe."""
    config = db.query(ConfiguracionIA).filter(ConfiguracionIA.id == _CONFIG_ID).first()
    if not config:
        config = ConfiguracionIA(
            id=_CONFIG_ID,
            base_url=settings.ollama_base_url.rstrip("/") + "/v1",
            api_key="",
            modelo=settings.ollama_model,
        )
        db.add(config)
        db.commit()
        db.refresh(config)
    return config


def actualizar_configuracion_ia(db: Session, base_url: str, modelo: str, api_key: str | None) -> ConfiguracionIA:
    """Actualiza base_url/modelo. Si `api_key` viene vacío/None, conserva la ya guardada."""
    config = obtener_configuracion_ia(db)
    config.base_url = base_url.rstrip("/")
    config.modelo = modelo
    if api_key:
        config.api_key = api_key
    db.commit()
    db.refresh(config)
    return config


def _completar_chat_openai(
    config: ConfiguracionIA,
    mensaje_usuario: str,
    datos_disponibles: str,
    historial: list[dict] | None = None,
) -> str:
    """
    Llama a `{base_url}/chat/completions` siguiendo el estándar de la API de OpenAI
    (Chat Completions). Compatible tanto con proveedores en la nube (OpenAI, Groq, ...)
    como con servidores locales que exponen ese mismo contrato (Ollama, LM Studio, ...).
    Incluye los últimos turnos de la conversación para que el modelo entienda preguntas
    de seguimiento ("dame más detalles") sin necesitar repetir todo el contexto a mano.
    Lanza la excepción tal cual si algo falla — el llamador decide cómo degradar.
    """
    headers = {"Authorization": f"Bearer {config.api_key or 'sin-api-key'}"}

    messages = [{"role": "system", "content": _SYSTEM_PROMPT_CHAT}]
    for turno in (historial or [])[-6:]:
        rol = "assistant" if turno.get("autor") == "bot" else "user"
        texto = turno.get("texto", "")
        if texto:
            messages.append({"role": rol, "content": texto})
    messages.append({
        "role": "user",
        "content": f"Datos disponibles:\n{datos_disponibles}\n\nMensaje del cliente: {mensaje_usuario}",
    })

    payload = {
        "model": config.modelo,
        "messages": messages,
        "temperature": 0.4,
    }
    respuesta = httpx.post(
        f"{config.base_url}/chat/completions",
        headers=headers,
        json=payload,
        timeout=45.0,
    )
    respuesta.raise_for_status()
    data = respuesta.json()
    return data["choices"][0]["message"]["content"].strip()


def probar_configuracion_ia(db: Session) -> dict:
    """Prueba la configuración actual con un mensaje simple, para que el admin valide su setup."""
    config = obtener_configuracion_ia(db)
    try:
        texto = _completar_chat_openai(config, "hola", "ninguno")
        return {"ok": True, "respuesta": texto, "error": None}
    except Exception as exc:
        return {"ok": False, "respuesta": None, "error": str(exc)}


def _resumen_catalogo_completo(db: Session) -> str:
    """
    Lista compacta de TODO el catálogo activo (nombre, categoría, precio, descripción).
    Se le pasa siempre a la IA en preguntas sobre productos, para que tenga contexto
    completo de la tienda y pueda responder preguntas de seguimiento o comparaciones
    sin depender únicamente de las palabras clave que detectó el motor de reglas.
    """
    productos = (
        db.query(Producto)
        .options(joinedload(Producto.categoria))
        .filter(Producto.activo.is_(True))
        .order_by(Producto.categoria_id, Producto.nombre)
        .all()
    )
    if not productos:
        return "(catálogo vacío)"
    lineas = []
    for p in productos:
        desc = f" — {p.descripcion}" if p.descripcion else ""
        categoria = p.categoria.nombre if p.categoria else "Sin categoría"
        lineas.append(f"- {p.nombre} ({categoria}), ${float(p.precio):.2f}{desc}")
    return "\n".join(lineas)


def _generar_respuesta_ia(
    db: Session, mensaje_usuario: str, datos_disponibles: str, historial: list[dict] | None = None
) -> str | None:
    """
    Le pide al proveedor de IA configurado (Ollama local, OpenAI, etc. — ver ConfiguracionIA)
    que redacte la respuesta final del chatbot en base a los datos reales ya obtenidos de la
    base de datos (grounding) y al historial de la conversación. Si el proveedor no responde
    por cualquier motivo, devuelve None para que el llamador use el texto de respaldo por reglas.
    """
    config = obtener_configuracion_ia(db)
    try:
        texto = _completar_chat_openai(config, mensaje_usuario, datos_disponibles, historial)
        return texto or None
    except Exception:
        # Proveedor caído, modelo inexistente, api_key inválida, timeout, etc.: degradar sin romper el chat.
        return None


def procesar_mensaje_chat(
    db: Session, cliente_id: int, mensaje: str, historial: list[dict] | None = None
) -> dict:
    """
    CU21: clasifica la intención del mensaje (reglas por palabras clave), busca los datos reales
    correspondientes y le pide al proveedor de IA configurado que redacte la respuesta final,
    usando también el historial de la conversación para entender preguntas de seguimiento
    ("dame más detalles"). Si el proveedor no está disponible, usa el texto de respaldo por reglas.
    """
    texto_norm = _normalizar(mensaje)
    intencion = _detectar_intencion(texto_norm)
    resultado = _resolver_intencion(db, cliente_id, intencion, texto_norm)

    datos_para_ia = resultado["respuesta"]
    if intencion in ("producto", "recomendacion"):
        # Siempre le damos el catálogo completo como contexto de fondo, además de lo que
        # haya encontrado la búsqueda puntual o el motor de recomendaciones, para que pueda
        # responder seguimientos, comparaciones y pedidos puntuales (ej. "recomendame un
        # vestido de gala") sin quedarse solo con el historial de compras del cliente.
        datos_para_ia += "\n\nCatálogo completo activo (contexto de referencia):\n" + _resumen_catalogo_completo(db)

    respuesta_ia = _generar_respuesta_ia(db, mensaje, datos_para_ia, historial)
    if respuesta_ia:
        resultado = {**resultado, "respuesta": respuesta_ia}
    return resultado


def _resolver_intencion(db: Session, cliente_id: int, intencion: str, texto_norm: str) -> dict:
    if intencion == "saludo":
        return _responder_saludo()
    if intencion == "agradecimiento":
        return _responder_agradecimiento()
    if intencion == "ayuda":
        return _responder_ayuda()
    if intencion == "recomendacion":
        return _responder_recomendacion(db, cliente_id, texto_norm)
    if intencion == "reservas":
        return _responder_reservas(db, cliente_id)
    if intencion == "sucursales":
        return _responder_sucursales(db)
    return _responder_producto(db, texto_norm)
