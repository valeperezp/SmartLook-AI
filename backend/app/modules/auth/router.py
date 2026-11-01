from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy.orm import Session

from app.modules.auth import schemas, service
from app.modules.usuarios.models import Usuario
from app.modules.usuarios.schemas import UsuarioOut
from app.shared.db.session import get_db

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/registro", response_model=UsuarioOut, status_code=201)
def registrar(data: schemas.RegistroRequest, db: Session = Depends(get_db)):
    return service.registrar_usuario(db, data)


@router.post("/login", response_model=schemas.TokenResponse)
async def login(request: Request, db: Session = Depends(get_db)):
    username = None
    password = None
    empresa = None  # slug opcional: iniciar sesión en el contexto de esa empresa (CU1)

    try:
        body = await request.json()
        if isinstance(body, dict):
            username = body.get("username") or body.get("email")
            password = body.get("password")
            empresa = body.get("empresa")
    except Exception:
        pass

    if not username or not password:
        try:
            form = await request.form()
            username = form.get("username") or form.get("email")
            password = form.get("password")
            empresa = form.get("empresa")
        except Exception:
            pass

    if not username or not password:
        raise HTTPException(status_code=422, detail="Email y contraseña son requeridos")

    empresa = str(empresa).strip() if empresa else None
    usuario = service.autenticar_usuario(db, str(username).strip(), str(password), empresa)
    if not usuario:
        raise HTTPException(status_code=401, detail="Email o contraseña incorrectos")
    return schemas.TokenResponse(access_token=service.emitir_token(usuario))


@router.get("/me", response_model=UsuarioOut)
def me(usuario: Usuario = Depends(service.get_current_user)):
    return usuario
