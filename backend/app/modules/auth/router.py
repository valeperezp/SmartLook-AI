"""Endpoints HTTP del módulo Auth."""
from fastapi import APIRouter, Depends, HTTPException
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
def login(form_data: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(get_db)):
    usuario = service.autenticar_usuario(db, form_data.username, form_data.password)
    if not usuario:
        raise HTTPException(status_code=401, detail="Email o contraseña incorrectos")
    return schemas.TokenResponse(access_token=service.emitir_token(usuario))


@router.get("/me", response_model=UsuarioOut)
def me(usuario: Usuario = Depends(service.get_current_user)):
    return usuario
