# Propuesta de esquema PostgreSQL para Finora

**Estado:** diseño para revisión; no es una migración SQL ejecutable.  
**Rama:** docs/postgresql-migration-plan  
**Base de referencia:** auditoría de SQLite local, versión 6.  
**No realizado:** no se ha creado una base de datos, ejecutado SQL, cambiado código de la app, importado datos reales, fusionado el PR ni publicado una versión.

## 1. Decisiones de diseño recomendadas

1. **Conservar el ID de usuario actual como texto.** Los usuarios locales usan usr_<uuid sin guiones>. PostgreSQL puede almacenarlo como TEXT; cambiarlo a UUID canónico ahora añadiría un mapeo innecesario. Validar el formato al crear identidades nuevas, pero no transformar IDs históricos automáticamente.
2. **Usar UUID estables para entidades financieras sincronizables.** Cada cuenta, categoría, transacción y transferencia tendrá un sync_id UUID generado localmente y conservado entre dispositivos. Las claves enteras de SQLite se mantienen como IDs internos durante la transición.
3. **Dinero en unidades menores enteras.** Las columnas enteras son la fuente de verdad. No usar REAL/FLOAT en el modelo remoto. La política de moneda debe ser explícita: no interpretar siempre el valor como “centavos” sin conocer la moneda. Si Finora soportará varias monedas, cada cuenta/movimiento deberá identificar la moneda y aplicar su precisión según una regla documentada.
4. **Propietario obligatorio para datos privados.** accounts, transactions y transfers siempre pertenecen a un usuario. Solo las categorías definidas expresamente como compartidas pueden carecer de propietario.
5. **Integridad en la base y en la API.** La API toma el usuario desde la sesión autenticada, no desde un user_id confiado al cliente. PostgreSQL agrega restricciones y claves foráneas compuestas para bloquear relaciones cruzadas entre usuarios.
6. **Sincronización separada de backups.** Una operación de sync tendrá idempotencia, control de versión y cursor; no reutilizar finora_backup_imports como si fuera un protocolo de sincronización.

## 2. Modelo propuesto por tabla

Los nombres son conceptuales y pueden ajustarse al estilo definitivo del backend.

### users

| Campo | Tipo conceptual | Regla |
|---|---|---|
| id | TEXT | PK; conservar usr_<uuid sin guiones> |
| first_name, last_name | TEXT | Obligatorios tras normalización y validación |
| login_identifier | TEXT | Único tras normalización; tipo exacto pendiente de decisión |
| password_hash | TEXT | Solo hash generado con algoritmo remoto; nunca contraseña |
| status | TEXT/ENUM | Estado de cuenta definido por el backend |
| created_at, updated_at | TIMESTAMPTZ | Generados por servidor |
| last_login_at | TIMESTAMPTZ NULL | Informativo |

**Pendiente obligatorio:** el registro local actual no pide email ni nombre de usuario único; solo nombre, apellido y contraseña. Antes de habilitar cuentas remotas hay que decidir cómo se identifica y recupera una cuenta. No asumir que nombre+apellido es único ni permitir recuperación insegura. No migrar hashes locales a ciegas: probar una transición compatible o pedir restablecer la contraseña.

### accounts

| Campo | Tipo conceptual | Regla |
|---|---|---|
| sync_id | UUID | PK remota y estable |
| user_id | TEXT | NOT NULL, FK a users.id |
| name | TEXT | NOT NULL |
| type | TEXT/ENUM | Valores aceptados documentados |
| initial_balance_minor | BIGINT | NOT NULL; unidad menor de la moneda |
| currency_code | CHAR(3) | ISO 4217 si se aprueba soporte multimoneda; pendiente |
| is_archived | BOOLEAN | NOT NULL, default false |
| created_at, updated_at | TIMESTAMPTZ | Fechas UTC del servidor |
| version | BIGINT | Versión monotónica para concurrencia |
| deleted_at | TIMESTAMPTZ NULL | Tombstone de sync; no borrar físicamente al inicio |

Reglas: saldo inicial no negativo si se conserva la regla actual; índices por propietario y fecha de actualización; unicidad de propietario e ID para soportar claves foráneas compuestas.

### categories

| Campo | Tipo conceptual | Regla |
|---|---|---|
| sync_id | UUID | Identificador estable |
| user_id | TEXT NULL | NULL solo para categorías globales administradas por el sistema |
| name | TEXT | NOT NULL |
| type | TEXT/ENUM | En el modelo actual: income o expense |
| is_default | BOOLEAN | Semántica a documentar; no sustituye al propietario |
| created_at, updated_at | TIMESTAMPTZ | UTC |
| version | BIGINT | Control de concurrencia |
| deleted_at | TIMESTAMPTZ NULL | Tombstone, respetando dependencias |

Reglas: separar claramente categorías del sistema y categorías personales. Una categoría global no debe ser editable/eliminable por un usuario normal. Las categorías privadas solo son visibles por su propietario. Definir unicidad con política de normalización de nombre y tipo; no imponerla hasta decidir si se permiten nombres duplicados.

### transactions

| Campo | Tipo conceptual | Regla |
|---|---|---|
| sync_id | UUID | PK estable |
| user_id | TEXT | NOT NULL, propietario |
| account_sync_id | UUID | NOT NULL, cuenta del mismo usuario |
| category_sync_id | UUID | NOT NULL, categoría global o del mismo usuario |
| type | TEXT/ENUM | income o expense según el modelo actual |
| amount_minor | BIGINT | NOT NULL y mayor que cero |
| currency_code | CHAR(3) | Validado contra la cuenta; política por definir |
| description | TEXT NULL | Longitud máxima definida por API |
| occurred_at | TIMESTAMPTZ | Fecha del movimiento |
| created_at, updated_at | TIMESTAMPTZ | UTC |
| version | BIGINT | Control de concurrencia |
| deleted_at | TIMESTAMPTZ NULL | Tombstone de sincronización |

Restricciones: FK compuesta de cuenta y propietario; una transacción no puede apuntar a una cuenta ajena. La categoría requiere validación que permita categorías globales o privadas del mismo usuario; no basta aceptar cualquier category_sync_id. Índices por propietario y fecha, y por propietario/cuenta/fecha.

### transfers

| Campo | Tipo conceptual | Regla |
|---|---|---|
| sync_id | UUID | PK estable |
| user_id | TEXT | NOT NULL |
| source_account_sync_id | UUID | NOT NULL |
| destination_account_sync_id | UUID | NOT NULL |
| amount_minor | BIGINT | NOT NULL y mayor que cero |
| currency_code | CHAR(3) | Debe coincidir en ambas cuentas, salvo conversión explícita |
| description | TEXT NULL | Validada |
| occurred_at | TIMESTAMPTZ | Fecha de transferencia |
| created_at, updated_at | TIMESTAMPTZ | UTC |
| version | BIGINT | Control de concurrencia |
| deleted_at | TIMESTAMPTZ NULL | Tombstone |

Restricciones: ambas cuentas pertenecen al mismo usuario; las cuentas deben ser distintas; monto positivo. Una transferencia entre monedas diferentes no se permitirá hasta diseñar tasas, importes de origen/destino y redondeos.

### Tablas auxiliares de sincronización

- **sync_operations:** clave idempotente única por usuario/operación, tipo de entidad, resultado y fecha. Repetir una petición tras timeout no debe crear duplicados.
- **sync_changes (o equivalente):** cursor monotónico por usuario, entidad, versión, operación y fecha para descargar cambios incrementales.
- **Outbox local SQLite:** cola durable de operaciones pendientes con identificador de operación, estado e intentos; se implementará en una migración local posterior y separada.
- **Mapeo local:** conservar los IDs enteros existentes y relacionarlos con sync_id; no cambiar PKs SQLite durante el primer paso.
- **Tombstones:** los borrados se replican como cambios hasta que los dispositivos pertinentes los hayan procesado. La purga física queda para una política posterior.

Los tokens de renovación deben poder revocarse y almacenarse en hash en el servidor. El almacenamiento de tokens en cada plataforma debe diseñarse antes de implementarlo.

## 3. Integridad y autorización

1. La identidad del usuario viene del middleware de autenticación.
2. Cada consulta y mutación financiera se restringe por propietario.
3. Las claves foráneas compuestas bloquean movimientos o transferencias con cuentas de otro propietario.
4. La API comprueba que la categoría sea global o del propietario autenticado y que su tipo corresponda al movimiento.
5. El servidor valida monto, moneda, tipo, tamaño de campos, fechas e IDs; no confía solo en Flutter.
6. Las operaciones relacionadas se aplican dentro de transacciones SQL atómicas.
7. Pruebas negativas obligatorias: usuario A intenta leer/editar/borrar/exportar datos de B; A intenta usar cuenta o categoría privada de B; A intenta transferir entre cuentas de A y B.
8. Considerar RLS como defensa adicional, pero probar el rol de conexión y el contexto por petición; no confiar en RLS sin validar su configuración real.

## 4. Política monetaria antes del SQL

El esquema local convierte a unidades menores mediante round(amount * 100), pero eso no demuestra que todas las monedas tengan dos decimales ni que los datos antiguos estén libres de discrepancias.

Antes de migrar:
- medir filas con amount_minor o initial_balance_minor nulos;
- comparar valores enteros con el redondeo del REAL histórico y reportar discrepancias;
- decidir moneda por cuenta y regla de precisión;
- bloquear importes no positivos en transacciones/transferencias y decidir si un saldo inicial negativo es válido;
- usar enteros grandes con límites de negocio en servidor;
- no corregir discrepancias silenciosamente: generar un informe y exigir una regla de reconciliación.

## 5. Estrategia de conflicto propuesta

- **Creación:** UUID estable + idempotencia; reintentos no duplican entidades.
- **Edición de cuenta/categoría:** control optimista por version; conflicto devuelto al cliente para resolverlo explícitamente.
- **Movimientos y transferencias:** no sobrescribir silenciosamente durante sync; correcciones como actualización versionada o evento de corrección auditado.
- **Eliminación:** tombstone versionado; verificar dependencias y propagar antes de purgar.
- **Cambios offline simultáneos:** el servidor devuelve conflicto y estado remoto; el cliente conserva el cambio local pendiente hasta resolverlo.
- **Orden:** cursor del servidor para sync incremental; los relojes de dispositivo no determinan por sí solos qué cambio gana.

Esta es una recomendación inicial, no una política activada en código.

## 6. Secuencia segura de implementación

1. Aprobar identidad remota, stack, moneda/precisión y política de conflictos.
2. Diseñar migraciones PostgreSQL versionadas y reversibles cuando sea posible; separar migraciones de esquema y de datos.
3. Crear pruebas con PostgreSQL temporal y usuarios/datos ficticios.
4. Validar restricciones y aislamiento antes de endpoints financieros.
5. Añadir UUID a entidades locales mediante una nueva migración SQLite, con backfill transaccional y pruebas de reinicio.
6. Añadir outbox/cursor e implementar sync en piloto con datos sintéticos.
7. Crear herramienta de importación con vista previa y consentimiento; conservar SQLite y backups.
8. Ensayar backup/restauración de PostgreSQL y rollback a modo local.
9. Solo después de aprobar los resultados, proponer staging. Producción y datos reales requieren autorización separada.

## 7. Aprobaciones pendientes

- **Inicio de sesión remoto:** email verificado, nombre de usuario único u otra alternativa segura; recuperación de cuenta.
- **Backend:** confirmar Node.js LTS + TypeScript + Fastify + PostgreSQL.
- **Moneda:** moneda fija o múltiples monedas por cuenta; precisión y transferencias entre monedas.
- **Conflictos:** aceptar o ajustar la estrategia propuesta por tipo de entidad.
- **Despliegue:** proveedor, región, cifrado, retención de backups, RPO/RTO y acceso a secretos.

**Conclusión:** esta propuesta define una dirección concreta, pero no autoriza ejecutar migraciones. Tras cerrar estas decisiones, el siguiente entregable será SQL versionado con restricciones y pruebas automáticas en una base temporal; nunca contra producción durante esta fase.
