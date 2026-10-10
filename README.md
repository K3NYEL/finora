# Finora

Aplicación de finanzas personales desarrollada con Flutter para organizar cuentas, ingresos, gastos y movimientos desde un solo lugar.

## Características

- Gestión de cuentas financieras y movimientos.
- Registro de ingresos, gastos y transferencias.
- Resúmenes y estadísticas por categoría.
- Base de datos local con SQLite.
- Copias de seguridad y restauración mediante archivos JSON.
- Preferencias de tema y moneda de visualización.
- Comprobación de actualizaciones de la aplicación.
- Estructura preparada para conectar servicios remotos de Finora.

## Tecnología

- Flutter y Dart
- SQLite
- Riverpod para el estado de la aplicación
- GoRouter para la navegación
- GitHub Actions para validación y publicación

## Requisitos

- Flutter SDK compatible con la versión indicada en el repositorio.
- Dart incluido con Flutter.
- Android SDK para compilar la aplicación Android.

## Ejecutar en desarrollo

Clona el repositorio e instala las dependencias:

```bash
git clone https://github.com/K3NYEL/finora.git
cd finora
flutter pub get
```

Ejecuta en un dispositivo disponible:

```bash
flutter run
```

Comprueba el proyecto con:

```bash
flutter analyze
flutter test
```

## Compilar para Android

```bash
flutter build apk --release
```

El archivo generado se encuentra normalmente en `build/app/outputs/flutter-apk/`.

## Datos y privacidad

Finora utiliza SQLite para almacenar datos financieros localmente en el dispositivo. Las copias de seguridad exportadas son archivos JSON sin cifrar y pueden contener información financiera legible. Guárdalas en una ubicación privada y comparte esos archivos únicamente con personas de confianza.

La sincronización remota requiere que el servicio de servidor correspondiente esté configurado. No asumas que los datos locales se sincronizan automáticamente.

## Estado del proyecto

Finora continúa en desarrollo. Algunas funciones remotas pueden depender de la configuración del servidor y de la versión instalada. Consulta las [publicaciones del repositorio](https://github.com/K3NYEL/finora/releases) para conocer las versiones disponibles.

## Licencia

No se ha especificado una licencia pública en este repositorio. No asumas que el código puede reutilizarse o redistribuirse sin autorización.
