"""
Tests del vestidor con mocks de Replicate.
NO llaman al modelo real. Costo: $0.
"""
import pytest
from unittest.mock import patch, MagicMock
from datetime import datetime, timedelta
from fastapi.testclient import TestClient
from app.main import app
from app.shared.db.session import SessionLocal
from app.modules.vestidor.models import VestidorGeneracion
from app.modules.usuarios.models import Usuario
from app.modules.catalogo.models import Producto
from app.shared.security import create_access_token

client = TestClient(app)


def _get_cliente_token():
    """Genera un token de cliente autenticado."""
    db = SessionLocal()
    usuario = db.query(Usuario).filter(Usuario.rol == "cliente").first()
    db.close()
    return create_access_token({"sub": str(usuario.id), "rol": "cliente"})


def _get_producto_con_imagen():
    """Obtiene un producto con imagen válida."""
    db = SessionLocal()
    p = db.query(Producto).filter(Producto.imagen_url.isnot(None)).first()
    db.close()
    return p


# ──────────────────────────────────────
# TEST 1: Validación de token faltante
# ──────────────────────────────────────
def test_sin_token_replicate():
    """Si no hay REPLICATE_API_TOKEN, debe fallar con 503."""
    with patch("app.shared.core.config.settings.replicate_api_token", ""):
        token = _get_cliente_token()
        producto = _get_producto_con_imagen()
        files = {"foto": ("test.jpg", b"\x89PNG\r\n\x1a\n", "image/jpeg")}
        r = client.post(
            "/vestidor/generar",
            data={"producto_id": producto.id},
            files=files,
            headers={"Authorization": f"Bearer {token}"},
        )
        assert r.status_code == 503
        assert "REPLICATE_API_TOKEN no configurado" in r.text
        print("[PASS] Test 1: Sin token → 503 OK")


# ──────────────────────────────────────
# TEST 2: Producto sin imagen
# ──────────────────────────────────────
def test_producto_sin_imagen():
    """Producto sin imagen_url → 400."""
    db = SessionLocal()
    producto = db.query(Producto).filter(Producto.imagen_url.is_(None)).first()
    db.close()

    if not producto:
        print("[SKIP] Test 2: No hay productos sin imagen en BD")
        return

    token = _get_cliente_token()
    files = {"foto": ("test.jpg", b"\x89PNG\r\n\x1a\n", "image/jpeg")}
    r = client.post(
        "/vestidor/generar",
        data={"producto_id": producto.id},
        files=files,
        headers={"Authorization": f"Bearer {token}"},
    )
    assert r.status_code == 400
    assert "no tiene imagen" in r.text
    print("[PASS] Test 2: Producto sin imagen → 400 OK")


# ──────────────────────────────────────
# TEST 3: Archivo no imagen
# ──────────────────────────────────────
def test_archivo_no_imagen():
    """Archivo .txt → 400."""
    token = _get_cliente_token()
    producto = _get_producto_con_imagen()
    files = {"foto": ("test.txt", b"texto plano", "text/plain")}
    r = client.post(
        "/vestidor/generar",
        data={"producto_id": producto.id},
        files=files,
        headers={"Authorization": f"Bearer {token}"},
    )
    assert r.status_code == 400
    assert "debe ser una imagen" in r.text
    print("[PASS] Test 3: Archivo no imagen → 400 OK")


# ──────────────────────────────────────
# TEST 4: Imagen demasiado grande
# ──────────────────────────────────────
def test_imagen_demasiado_grande():
    """Imagen > 10MB → 400."""
    token = _get_cliente_token()
    producto = _get_producto_con_imagen()
    big_content = b"\x89PNG\r\n\x1a\n" + (b"\x00" * (11 * 1024 * 1024))  # 11 MB
    files = {"foto": ("big.jpg", big_content, "image/jpeg")}
    r = client.post(
        "/vestidor/generar",
        data={"producto_id": producto.id},
        files=files,
        headers={"Authorization": f"Bearer {token}"},
    )
    assert r.status_code == 400
    assert "10MB" in r.text or "10 MB" in r.text
    print("[PASS] Test 4: Imagen gigante → 400 OK")


# ──────────────────────────────────────
# TEST 5: Cache funciona (no llama a Replicate)
# ──────────────────────────────────────
def test_cache_evita_llamada_replicate():
    """
    Si ya hay una generación en las últimas 24h para (usuario, producto),
    debe devolverla sin llamar a Replicate.
    """
    token = _get_cliente_token()
    producto = _get_producto_con_imagen()

    # Limpia generaciones previas del usuario (para que el test sea repetible
    # y no dependa de residuos de corridas anteriores) e inserta una manual.
    db = SessionLocal()
    usuario = db.query(Usuario).filter(Usuario.rol == "cliente").first()
    db.query(VestidorGeneracion).filter(
        VestidorGeneracion.usuario_id == usuario.id
    ).delete()
    gen = VestidorGeneracion(
        usuario_id=usuario.id,
        producto_id=producto.id,
        imagen_resultado_url="https://fake-url.test/cache-test.jpg",
    )
    db.add(gen)
    db.commit()
    db.close()

    # Mockear replicate.Client para verificar que NO se llama
    with patch("replicate.Client") as mock_client:
        files = {"foto": ("test.jpg", b"\x89PNG\r\n\x1a\n", "image/jpeg")}
        r = client.post(
            "/vestidor/generar",
            data={"producto_id": producto.id},
            files=files,
            headers={"Authorization": f"Bearer {token}"},
        )

        # Debe devolver la URL cacheada
        assert r.status_code == 200
        assert r.json()["desde_cache"] is True
        assert r.json()["imagen_resultado_url"] == "https://fake-url.test/cache-test.jpg"

        # Verificar que Replicate NUNCA se llamó
        assert mock_client.call_count == 0
        print("[PASS] Test 5: Cache evita llamada a Replicate OK")


# ──────────────────────────────────────
# TEST 6: Límite diario
# ──────────────────────────────────────
def test_limite_diario_alcanzado():
    """Si el usuario ya hizo N generaciones hoy, debe rechazar con 429."""
    from app.shared.core.config import settings

    token = _get_cliente_token()

    db = SessionLocal()
    usuario = db.query(Usuario).filter(Usuario.rol == "cliente").first()
    productos = (
        db.query(Producto).filter(Producto.imagen_url.isnot(None)).limit(2).all()
    )
    if len(productos) < 2:
        db.close()
        print("[SKIP] Test 6: Hacen falta 2 productos con imagen para este test")
        return
    # IDs planos, no las instancias ORM — evita usar objetos "expirados" luego de un commit.
    producto_relleno_id = productos[0].id
    producto_objetivo_id = productos[1].id

    # Limpiar generaciones previas del usuario para partir de un conteo conocido
    db.query(VestidorGeneracion).filter(
        VestidorGeneracion.usuario_id == usuario.id
    ).delete()
    db.commit()

    # Insertar (límite configurado) generaciones hoy contra un producto "de relleno"
    # (IDs reales, la tabla tiene FK a productos) — el conteo del límite es por
    # usuario, no por producto, así que alcanza con repetir uno solo.
    for i in range(settings.vestidor_max_por_usuario_dia):
        gen = VestidorGeneracion(
            usuario_id=usuario.id,
            producto_id=producto_relleno_id,
            imagen_resultado_url=f"https://fake.test/limit-{i}.jpg",
        )
        db.add(gen)
    db.commit()
    db.close()

    with patch("replicate.Client") as mock_client:
        files = {"foto": ("test.jpg", b"\x89PNG\r\n\x1a\n", "image/jpeg")}
        r = client.post(
            "/vestidor/generar",
            # producto distinto al "de relleno" → no hay cache hit, se llega al chequeo de límite
            data={"producto_id": producto_objetivo_id},
            files=files,
            headers={"Authorization": f"Bearer {token}"},
        )

        assert r.status_code == 429
        assert "Limite diario alcanzado" in r.text
        assert mock_client.call_count == 0
        print("[PASS] Test 6: Límite diario → 429 OK")


# ──────────────────────────────────────
# TEST 7: Mock completo de Replicate exitoso
# ──────────────────────────────────────
def test_generacion_mock_exitosa():
    """Simula un Replicate exitoso SIN llamar al modelo real."""
    # Limpiar generaciones previas para evitar cache
    db = SessionLocal()
    usuario = db.query(Usuario).filter(Usuario.rol == "cliente").first()
    db.query(VestidorGeneracion).filter(
        VestidorGeneracion.usuario_id == usuario.id
    ).delete()
    db.commit()
    db.close()

    token = _get_cliente_token()
    producto = _get_producto_con_imagen()

    # Mockear solo el método .run() del cliente
    with patch("replicate.Client") as MockClient:
        mock_instance = MagicMock()
        mock_instance.run.return_value = "https://fake-replicate.test/mock-result.jpg"
        MockClient.return_value = mock_instance

        files = {"foto": ("test.jpg", b"\x89PNG\r\n\x1a\n", "image/jpeg")}
        r = client.post(
            "/vestidor/generar",
            data={"producto_id": producto.id},
            files=files,
            headers={"Authorization": f"Bearer {token}"},
        )

        assert r.status_code == 200
        data = r.json()
        assert data["imagen_resultado_url"] == "https://fake-replicate.test/mock-result.jpg"
        assert data["desde_cache"] is False

        # Verificar que se llamó EXACTAMENTE 1 vez (pero en el mock)
        assert mock_instance.run.call_count == 1

        # Verificar el modelo usado
        call_args = mock_instance.run.call_args
        assert "idm-vton" in str(call_args)
        print("[PASS] Test 7: Generación mock exitosa → 200 OK sin gastar crédito")


if __name__ == "__main__":
    print("=" * 60)
    print("TESTS DEL VESTIDOR (SIN GASTAR CRÉDITO)")
    print("=" * 60)
    test_sin_token_replicate()
    test_producto_sin_imagen()
    test_archivo_no_imagen()
    test_imagen_demasiado_grande()
    test_cache_evita_llamada_replicate()
    test_limite_diario_alcanzado()
    test_generacion_mock_exitosa()
    print("=" * 60)
    print("TODOS LOS TESTS PASARON - COSTO: $0.00")
    print("=" * 60)
