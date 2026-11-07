FROM python:3.12-slim

WORKDIR /app

COPY requirements.lock.txt .
RUN pip install --no-cache-dir -r requirements.lock.txt

COPY app ./app
COPY migraciones ./migraciones
COPY seeds ./seeds

# Archivos subidos (QR de sucursales, comprobantes, copia local de modelos de ML).
# En Railway conviene montar un volumen en /app/uploads para que no se pierdan en cada despliegue.
RUN mkdir -p /app/uploads

EXPOSE 8000

# Producción: sin --reload y en el puerto que asigne la plataforma (Railway define $PORT).
# En desarrollo, docker-compose.yml reemplaza este comando por uno con --reload.
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000} --proxy-headers --forwarded-allow-ips='*'"]
