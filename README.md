# Finora

**Finora** es una aplicación de finanzas personales creada con Flutter para organizar el dinero de forma sencilla y mantener los datos bajo el control del usuario.

## Qué puedes hacer

- **Administrar cuentas financieras:** organiza tus cuentas y consulta sus balances.
- **Registrar movimientos:** guarda ingresos, gastos y transferencias.
- **Consultar estadísticas:** revisa resúmenes y distribuciones por categoría.
- **Personalizar categorías:** adapta los registros a tus necesidades.
- **Crear y restaurar copias de seguridad:** exporta tus datos y recupéralos cuando lo necesites.
- **Elegir la apariencia:** utiliza el tema claro, oscuro o el del sistema.
- **Comprobar actualizaciones:** revisa si hay una nueva versión disponible para Android.

## Privacidad y almacenamiento

Finora utiliza una arquitectura **local-first**: la base de datos SQLite del dispositivo es el almacenamiento principal de los datos financieros. Las copias de seguridad se guardan como archivos locales; actualmente, los archivos JSON de respaldo no están cifrados, por lo que deben conservarse en un lugar privado.

## Tecnologías

- Flutter y Dart
- SQLite (sqflite)
- Riverpod para el estado
- GoRouter para la navegación
- GitHub Actions para validar el proyecto y preparar compilaciones de Android

## Ejecutar en desarrollo

Necesitas tener instalado Flutter y las herramientas correspondientes a la plataforma de destino.

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

Para generar un APK de Android:

```bash
flutter build apk
```

## Estado del proyecto

Finora sigue en desarrollo. Las funciones y la compatibilidad pueden cambiar entre versiones. Consulta las [versiones publicadas](https://github.com/K3NYEL/finora/releases) para revisar las novedades disponibles.

## Repositorio

Código fuente: [K3NYEL/finora](https://github.com/K3NYEL/finora)
