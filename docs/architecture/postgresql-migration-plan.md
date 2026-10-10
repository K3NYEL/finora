# Plan de migración de Finora a PostgreSQL

**Estado:** propuesta técnica para revisión.  
**Alcance de este cambio:** documentación únicamente. No cambia el código de la app, el esquema SQLite, las versiones publicadas ni datos de usuarios. No crea ni modifica una base de datos de producción.

## 1. Objetivo y reglas de seguridad

Finora debe conservar el funcionamiento local y sin conexión mientras añade sincronización segura entre Android, Linux y web. PostgreSQL será la fuente central para los datos sincronizados; los clientes Flutter no se conectarán directamente a PostgreSQL.

Principios obligatorios:

- Mantener SQLite y las copias de seguridad actuales durante toda la transición.
- No desplegar ni migrar datos reales hasta aprobar el diseño, implementar pruebas y ensayar una restauración.
- No asignar automáticamente registros históricos sin propietario a la primera cuenta que inicie sesión.
- No confiar en un `user_id` enviado por el cliente para autorizar lecturas o escrituras. La API obtiene el usuario de la sesión autenticada.
- Usar UUID aleatorios para identidades de usuarios y para identificadores estables de sincronización. Se pueden conservar las claves enteras locales de SQLite durante la transición.
- Guardar dinero como unidades menores enteras (por ejemplo, centavos), evitando cálculos monetarios con punto flotante.
- No registrar contraseñas, tokens, datos financieros sensibles ni secretos en logs.
- Mantener exportación/restauración local compatible y probar aislamiento entre usuarios.

## 2. Arquitectura propuesta

```text
Flutter (Android / Linux / web)
        | HTTPS + sesión autenticada
        v
API de Finora (backend; propuesta: Node.js + TypeScript)
        | consultas parametrizadas y transacciones
        v
PostgreSQL
```

SQLite permanece en cada instalación para acceso sin conexión. La sincronización se añade después de disponer de API, esquema remoto y estrategia de resolución de conflictos.

### Stack de backend propuesto para aprobación

- Node.js LTS + TypeScript.
- Fastify para HTTP y validación de solicitudes.
- PostgreSQL con migraciones SQL versionadas y revisables.
- Consultas parametrizadas mediante el cliente `pg` o una capa equivalente.
- Contraseñas con Argon2id y parámetros mantenidos por una biblioteca fiable.
- Sesiones con tokens de acceso de corta duración y renovación rotativa/revocable; almacenar los hashes de los tokens de renovación.
- Secretos únicamente mediante variables de entorno/gestor de secretos del entorno de despliegue.
- HTTPS obligatorio fuera del entorno local.
- Pruebas de integración con una instancia PostgreSQL temporal; CI no debe depender de una base de datos de producción.

Este stack es una recomendación, no una decisión irreversible. No se añadirá ninguna dependencia ni backend hasta revisar y aprobar esta propuesta.

## 3. Modelo de datos remoto preliminar

Los nombres definitivos y las columnas deben ajustarse a los modelos reales de Finora antes de crear migraciones.

### `users`

- `id UUID PRIMARY KEY`, generado en el servidor.
- `first_name`, `last_name`.
- `email` o identificador de inicio de sesión normalizado, con restricción de unicidad si el producto confirma que el correo será obligatorio.
- `password_hash` (nunca contraseña en texto claro).
- `created_at`, `updated_at`, `last_login_at`.
- Estado de cuenta y campos necesarios para revocación, si se aprueban.

El registro debe validar contraseña y confirmación en el cliente y en el servidor; la confirmación no se almacena. La política de recuperación de cuenta debe diseñarse antes de habilitar cuentas remotas.

### Datos financieros

Tablas remotas equivalentes a cuentas, transacciones, transferencias y categorías, basadas en el esquema SQLite actual:

- Cada entidad sincronizable tendrá un UUID estable `sync_id` (o UUID como clave primaria remota).
- `user_id UUID NOT NULL` para datos privados, con claves foráneas a `users`.
- Las categorías globales podrán tener propietario nulo solo donde el modelo actual permita explícitamente categorías compartidas.
- Importes en unidades menores enteras; moneda y reglas de precisión definidas explícitamente.
- `created_at` y `updated_at`; considerar `deleted_at`/tombstones para propagar eliminaciones entre dispositivos.
- Restricciones e índices compuestos por propietario e identificador para hacer eficientes y seguras las consultas.

Las claves enteras actuales de SQLite no se cambiarán de golpe. Se añadirá una correspondencia explícita entre el ID local y el UUID de sincronización, preservando referencias entre transacciones, cuentas, transferencias y categorías.

## 4. Límites de autorización

- El middleware autentica la solicitud y construye una identidad de usuario confiable.
- Cada lectura, modificación y eliminación de datos privados filtra por el propietario derivado de esa identidad.
- Las operaciones de escritura validan las relaciones: una transacción no puede referenciar la cuenta de otro usuario.
- No exponer endpoints que permitan consultar un usuario arbitrario por ID.
- Probar ataques de acceso horizontal: usuario A intentando leer, cambiar, exportar o borrar los datos de B.
- Considerar políticas de seguridad por fila (RLS) como defensa adicional, sin sustituir la autorización correcta de la API.
- Limitar intentos de autenticación, validar entradas, configurar CORS de forma explícita y evitar mensajes de error que revelen si una cuenta existe.

## 5. Sincronización offline

La sincronización no forma parte de la primera migración de esquema; se implementará en una fase separada.

1. Añadir UUID estables a entidades locales y backfill transaccional sin perder relaciones.
2. Crear una bandeja local de cambios pendientes (outbox) y cursor/versión de sincronización.
3. Enviar lotes idempotentes con identificadores de operación únicos.
4. El servidor valida propietario, relaciones y versión antes de aplicar cada cambio.
5. Descargar cambios desde un cursor y aplicar el lote localmente en una transacción SQLite.
6. Definir conflictos por entidad. No usar simplemente “gana el último” para todas las operaciones financieras.
7. Replicar eliminaciones mediante tombstones hasta que todos los dispositivos pertinentes las hayan recibido.
8. Reintentar de forma segura ante falta de conexión, expiración de sesión o respuesta perdida.

## 6. Migración de datos y continuidad

- SQLite seguirá funcionando como base local y será la fuente de datos existente de cada usuario hasta que la sincronización se valide.
- No subir datos financieros locales automáticamente durante el inicio de sesión sin una explicación y consentimiento explícito.
- La importación inicial debe tener vista previa, conteos por tipo, validación de relaciones y una clave de idempotencia para evitar duplicados.
- Mantener los registros heredados sin propietario en cuarentena hasta que el usuario ejecute el flujo explícito de recuperación existente.
- Antes de importar: exportar backup, validar el formato, calcular conteos/checksums y comprobar espacio disponible.
- Tras importar: comparar conteos, importes agregados y relaciones; verificar que una segunda ejecución no duplique datos.
- Disponer de un procedimiento de rollback que desactive sincronización remota sin borrar los datos locales.

## 7. Fases y criterios de salida

### Fase 0 — Auditoría y diseño (actual)
- Confirmar versión y esquema real de SQLite, modelos, relaciones, autenticación y formato de backup.
- Aprobar stack, modelo de identidad, esquema remoto y estrategia de conflictos.
- Entregable: este documento revisado y un diagrama/modelo final.

### Fase 1 — Fundamentos aislados
- Crear backend y configuración local de desarrollo en una rama independiente.
- Añadir migraciones SQL iniciales y datos de prueba ficticios.
- CI ejecuta análisis, pruebas unitarias e integración con PostgreSQL.
- Criterio: migraciones repetibles desde cero y rollback/recuperación ensayados.

### Fase 2 — Autenticación y API
- Registro, inicio/cierre de sesión, renovación/revocación de sesión.
- Endpoints mínimos de perfil y prueba; no sincronizar datos financieros todavía.
- Criterio: pruebas negativas de autorización y credenciales, límites de solicitudes y logs sin secretos.

### Fase 3 — Sincronización piloto
- Añadir UUID locales, outbox, cursores e idempotencia.
- Probar modo offline, reintentos, conflictos, borrados y múltiples dispositivos con datos sintéticos.
- Criterio: no se pierden cambios ni se filtran datos entre usuarios.

### Fase 4 — Importación voluntaria
- Herramienta de vista previa/importación desde SQLite/backup.
- Ensayo repetido con copias de prueba y verificación de integridad.
- Criterio: importación repetible sin duplicados y procedimiento de recuperación probado.

### Fase 5 — Despliegue gradual
- Entorno de staging primero; secretos separados; TLS; backups automáticos y restauración verificada.
- Piloto voluntario y monitorización; posibilidad de desactivar el backend sin bloquear el uso local.
- No cambiar la versión estable ni eliminar SQLite hasta aprobar métricas y pruebas de recuperación.

## 8. Pruebas mínimas obligatorias

- Migraciones nuevas desde una base vacía y desde la versión previa.
- Restricciones de claves foráneas y consistencia de transferencias.
- Aislamiento de dos usuarios para todas las operaciones.
- Contraseñas no reversibles y tokens revocables.
- Importe de backup, reimportación idempotente y usuario distinto.
- Datos heredados sin propietario y flujo de recuperación explícita.
- Interrupción de red a mitad de sincronización, reintento y respuestas duplicadas.
- Conversión exacta de importes y límites numéricos.
- Copia de seguridad y restauración real de PostgreSQL en un entorno de prueba.
- Pruebas de Android, Linux y web antes de activar funciones remotas.

## 9. Decisiones pendientes antes de implementar

1. Confirmar el stack propuesto (Node.js/TypeScript + Fastify + PostgreSQL) o elegir otro.
2. Definir el identificador de inicio de sesión obligatorio y la recuperación de cuenta.
3. Elegir el entorno de despliegue y la política de backups/retención.
4. Aprobar reglas de conflicto de sincronización por tipo de entidad.
5. Aprobar el esquema final tras revisar todas las tablas y migraciones SQLite actuales.

**Próximo paso seguro:** completar la auditoría del esquema local y convertir este borrador en un esquema SQL revisable. No desplegar, crear credenciales de producción ni migrar datos reales en esta fase.
