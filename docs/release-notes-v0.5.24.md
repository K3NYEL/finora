# Finora v0.5.24 — notas de parche preparadas

## Cambios incluidos
- Mejora de la gestión de datos financieros, restauración y copias de seguridad locales.
- Preparación de la base del backend PostgreSQL y documentación de migración gradual, manteniendo SQLite como fuente local.
- Vinculación opcional de cuenta remota con almacenamiento seguro de sesión.
- La sincronización financiera remota continúa desactivada; no se suben datos financieros al vincular una cuenta.
- Endurecimiento del workflow de releases para compilar el tag exacto validado y reducir riesgos de discrepancia entre tag y rama.

## Antes de publicar
- Confirmar que los workflows de CI y compilación Android terminan correctamente en main.
- Validar el contrato entre el cliente y el backend con pruebas de integración sobre HTTPS.
- Confirmar que la firma de la APK coincide con la de la versión publicada anterior.
- No crear el tag ni publicar la release hasta aprobar esas comprobaciones.
