# Auditoría del esquema SQLite antes de PostgreSQL

**Estado:** hallazgos de solo lectura sobre `main`.  
**Base revisada:** `main` en la auditoría de octubre de 2026.  
**Cambios de esquema o datos:** ninguno.  
**Propósito:** documentar qué existe realmente antes de redactar migraciones PostgreSQL.

## 1. Esquema SQLite observado

La apertura de la base local declara la versión **6** en `lib/core/database/database.dart`. En una instalación nueva crea estas entidades y ejecuta las migraciones 002–006:

| Tabla | Campos/relaciones relevantes | Consideraciones para PostgreSQL |
|---|---|---|
| `users` | `id TEXT PRIMARY KEY`, `first_name`, `last_name`, `password_hash`, `created_at`, `last_login` | El ID local generado tiene formato `usr_<uuid sin guiones>`; no es un UUID canónico. Debe decidirse si se conserva como TEXT o se crea un mapeo explícito a UUID remoto. |
| `accounts` | PK entera autoincremental, `name`, `type`, `initial_balance REAL`, `initial_balance_minor INTEGER`, `created_at`, `is_archived`, `user_id TEXT` | `user_id` es nullable y no tiene FK declarada a `users`. Las claves enteras se referencian desde movimientos y transferencias. |
| `categories` | PK entera autoincremental, `name`, `type`, `is_default`, `user_id TEXT` | `user_id IS NULL` representa categorías compartidas/globales; las categorías privadas deben ser visibles solo para su propietario. No hay FK declarada a `users`. |
| `transactions` | PK entera, `account_id` FK a cuentas, `category_id` FK a categorías, `type`, `amount REAL`, `amount_minor INTEGER`, descripción, fecha, `user_id TEXT` | `user_id` nullable y sin FK. La entidad depende de una cuenta y una categoría; el servidor debe validar que las tres pertenezcan al mismo usuario o que la categoría sea global. |
| `transfers` | PK entera, cuenta origen/destino, `amount REAL`, `amount_minor INTEGER`, descripción, fecha, `user_id TEXT` | `user_id` nullable y sin FK. Ambas cuentas deben pertenecer al mismo propietario y ser distintas. |
| `legacy_data_migration` | Estado y contadores de registros sin propietario | Es un control local de recuperación; no debe convertirse automáticamente en datos financieros remotos ni desaparecer sin un plan explícito. |
| `finora_backup_imports` | checksum, `user_id TEXT`, fecha de importación | Se crea durante la restauración. Sirve para evitar repetir el mismo backup dentro de una cuenta local; el modelo remoto de idempotencia de sync es una función distinta. |

## 2. Migraciones locales existentes

- **Versión 2:** índices para búsquedas por cuenta, categoría, fecha y cuentas de transferencias.
- **Versión 3:** añade `initial_balance_minor` y `amount_minor` y los rellena con `ROUND(valor * 100)`.
- **Versión 4:** crea `users` y añade `user_id` a cuentas, categorías, transacciones y transferencias, además de índices.
- **Versión 5:** reservada/no-op.
- **Versión 6:** crea el registro de recuperación y asigna propiedad solo cuando se puede inferir inequívocamente desde cuentas ya asignadas; deja casos ambiguos pendientes.

No se debe reutilizar el número de versión local 6 para una futura migración SQLite. Las migraciones PostgreSQL tendrán su propia secuencia independiente.

## 3. Servicios y garantías existentes

### Autenticación local
- El registro pide nombre, apellido y contraseña; no se observó email ni otro identificador de inicio de sesión.
- El inicio de sesión busca por nombre y apellido y falla si hay varias coincidencias.
- Los IDs se generan con UUID aleatorio, con prefijo `usr_` y sin guiones.
- El código usa un formato de hash versionado PBKDF2-HMAC-SHA256 y mantiene compatibilidad con un formato heredado SHA-256 con sal.
- La sesión recordada se mantiene en almacenamiento de preferencias del dispositivo; esto no equivale a autenticación remota ni a un token de API.
- No copiar contraseñas en claro (ni incluirlas en backups). No asumir que el hash local se puede reutilizar directamente en el servidor: habrá que diseñar una transición compatible y probarla.

### Dinero
- El esquema mantiene columnas históricas `REAL` junto a columnas enteras de unidades menores.
- El repositorio prefiere `*_minor` cuando está disponible, pero estas columnas son nullable en el esquema observado.
- La propuesta remota debe usar enteros de unidades menores como fuente de verdad y definir una regla de conversión/validación para valores heredados, redondeos y monedas.

### Backups
- El JSON usa `format: finora-backup` y `schema_version: 1`.
- Exporta cuentas, categorías usadas, transacciones y transferencias del usuario; excluye credenciales/hash de contraseña.
- La restauración valida estructura y relaciones, remapea claves enteras y rechaza importar dos veces el mismo contenido a la misma cuenta.
- Es un backup local/importación, no un protocolo de sincronización: no contiene todavía UUID estables por entidad, cursores, versiones ni borrados replicables.

### Recuperación de registros heredados
- Hay un flujo de confirmación explícita con la frase `RECUPERAR MIS DATOS ANTIGUOS`.
- La migración 006 evita asignar automáticamente registros a quien se registre primero.
- Este comportamiento debe mantenerse; en el futuro la importación remota necesita vista previa, consentimiento y una estrategia de propiedad para datos ambiguos.

## 4. Riesgos y trabajo necesario antes de crear SQL remoto

1. **Identidad incompatible si se cambia sin mapeo:** los IDs de usuario locales son texto con prefijo, mientras que el borrador inicial plantea UUID PostgreSQL. Mantener el ID como `TEXT` o crear una tabla de correspondencia explícita; no transformar IDs sin un plan de reconciliación.
2. **Autenticación todavía solo local:** elegir identificador de cuenta remoto (correo u otro identificador verificado), recuperación de cuenta, límites de intentos y transición de credenciales antes de activar API remota.
3. **Restricciones de propietario insuficientes en SQLite:** PostgreSQL debe usar FKs y restricciones compuestas que impidan relacionar un movimiento con cuenta de otro usuario o una transferencia con cuentas de propietarios diferentes.
4. **Importes mixtos:** decidir el tratamiento de filas con `*_minor IS NULL` o discrepancias entre `REAL` y unidades menores; medir discrepancias con una auditoría previa y no corregirlas silenciosamente.
5. **Categorías globales y privadas:** definir unicidad, actualización y borrado de categorías globales frente a categorías propias; conservar `user_id NULL` solo para las compartidas aprobadas.
6. **UUID estable por entidad ausente:** cuentas, categorías, movimientos y transferencias usan IDs enteros locales. Añadir un `sync_id` UUID con backfill seguro y referencias explícitas antes de sincronizar múltiples dispositivos.
7. **Sin backend en el cliente actual:** `pubspec.yaml` contiene el paquete HTTP, pero el esquema revisado no evidencia una API remota implementada. No conectar Flutter directamente a PostgreSQL.
8. **Sincronización y backup son cosas distintas:** el backup actual no ofrece operaciones idempotentes por entidad, control de versiones concurrentes ni tombstones para borrados.

## 5. Propuesta de esquema PostgreSQL (borrador, aún no SQL ejecutable)

- `users`: ID estable; nombres; identificador de inicio de sesión verificado; hash de contraseña remoto; timestamps y estado de cuenta.
- `accounts`: UUID estable, `user_id` obligatorio, nombre/tipo, saldo inicial en unidades menores enteras, timestamps y estado de archivo.
- `categories`: UUID estable, propietario nullable solo para categorías globales, nombre/tipo y reglas de visibilidad.
- `transactions`: UUID estable, propietario obligatorio, referencias a cuenta/categoría, tipo, importe entero en unidades menores, descripción, fecha y timestamps.
- `transfers`: UUID estable, propietario obligatorio, referencias origen/destino, importe entero en unidades menores, descripción, fecha y timestamps.
- `sync_operations` o equivalente: idempotencia por operación, sin sustituir las restricciones de dominio.
- Campos de sincronización/versionado y tombstones se decidirán antes de implementar la API.

El esquema final deberá incluir claves foráneas compuestas o un diseño equivalente que impida relaciones cruzadas entre propietarios, índices por propietario y fecha, restricciones de importes/tipos, y una estrategia de categorías globales que no abra acceso a datos privados.

## 6. Plan de verificación antes de la primera migración

1. Ejecutar pruebas sobre una copia de SQLite, no sobre la base de datos del usuario.
2. Contar filas por tabla, filas sin propietario, importes con unidades menores nulas y diferencias entre importes heredados y minor units.
3. Verificar que todas las referencias de transacciones/transferencias apuntan a entidades existentes y con propietario compatible.
4. Crear un export de prueba, restaurarlo en una base temporal y comparar conteos, relaciones y sumas en unidades menores.
5. Implementar el primer esquema PostgreSQL con datos sintéticos y pruebas negativas de aislamiento entre dos usuarios.
6. Ensayar backup y restauración de PostgreSQL antes de plantear cualquier importación real.

## 7. Decisiones que necesitan aprobación

- ¿Se conserva `users.id` como TEXT compatible con `usr_<uuid>`, o se añade una correspondencia con UUID canónico remoto?
- ¿Qué identificador remoto usará el inicio de sesión? La app local actual no tiene correo.
- ¿Se aprueba el stack Node.js/TypeScript + Fastify + PostgreSQL propuesto en el plan principal?
- ¿Qué monedas y reglas de precisión debe soportar la versión remota?

**Conclusión:** el esquema local ya tiene aislamiento por `user_id` aplicado por el repositorio y una protección útil para datos heredados, pero todavía no equivale a un modelo remoto con restricciones fuertes. La siguiente etapa segura es acordar identidad y autenticación remotas, luego crear un esquema PostgreSQL independiente con restricciones de propietario y pruebas; no migrar datos reales todavía.
