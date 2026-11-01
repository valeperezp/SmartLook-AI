# Tests del vestidor: desactivados

`test_vestidor_mock.py.skip` se desactivó el 2026-10-29. La extensión `.skip` evita que pytest lo colecte.

**Por qué:** usaba `SessionLocal()` real contra Supabase y borraba filas reales de `vestidor_generaciones`
(además dejaba al usuario de prueba en el límite diario). Dos de sus siete tests también están obsoletos:
esperan `200` y `desde_cache`, pero `POST /vestidor/generar` ahora responde `202` con un `job_id`.

**Antes de reactivarlo:** migrarlo a una base de datos de test con fixtures y adaptarlo al flujo asíncrono.
Ver docs/auditoria-2026-10/F12 (pendiente de crear).
