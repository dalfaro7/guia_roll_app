# Reportes de campo sin fotos
Categorías: accidente en la vía, tráfico regulado, Ruta Cerrada, Control Policial, vida silvestre (monos, perezosos, otro con texto), strainer, cambio en la línea y rápido peligroso.
Cada reporte guarda autor, equipo, GPS, precisión, fecha de observación y recepción. Visible al mismo equipo y admin; staff consulta lista, operadores mapa y resolución.
Caduca una hora después de recibirse. API bloquea reportes vencidos; la tarea cada hora elimina registros incluso resueltos. No se cargan ni guardan fotos; no necesita un volumen para imágenes.
Antes de publicar: respaldo PostgreSQL, migración 20261025050000, comprobar scheduler Solid Queue y generar APK para probar en Honor. Los respaldos tienen su propia retención.

La visibilidad vence a los 60 minutos; la limpieza física se ejecuta cada hora, por lo que puede borrar el registro hasta casi dos horas después de su creación, si el scheduler funciona normalmente.


## Avisos y mapa móvil (preparados, no activados)

- expo-notifications registra un token por sesión autenticada. Al reutilizar un teléfono con otra cuenta el token se desvincula de la sesión anterior. Cerrar sesión elimina la sesión y sus destinatarios.
- Rails envía mediante Expo Push a Firebase/FCM en Android y, posteriormente, APNs en iOS. Proveedor desactivado salvo KAYAK_REPORT_PUSH_ENABLED=true. EXPO_ACCESS_TOKEN admite la protección adicional de Expo.
- Destinatarios: miembros activos actuales del equipo y administradores; excluye al autor. Se revalidan equipos, sesión y caducidad al enviar y al consultar detalle. El aviso externo es genérico y sin nombre, texto libre o GPS; incluye identificador opaco del evento, cuenta destinataria y vencimiento.
- TTL limita la espera del proveedor a la vida restante del reporte. Pantalla bloqueada depende de permisos Android, conectividad y configuración Firebase; no se garantiza recepción instantánea. Evento vencido/resuelto o acceso revocado no abre su detalle.
- Entregas por reporte/sesión evitan repetir envíos ya aceptados. Timeout de red tras aceptación del proveedor puede provocar duplicado (no hay garantía exactamente una vez). Acuse del proveedor no prueba lectura ni visualización por el teléfono.
- Recuperación de envíos pendientes cada minuto; limpieza de registros sigue CADA HORA. Historial de entregas se borra en cascada con reporte o sesión.
- Mapa móvil Leaflet/OpenStreetMap en WebView: solo pines de reportes autorizados, nunca posiciones de personas. Pulsar pin consulta nuevamente detalle autenticado. Requiere internet para cartografía.

### Configuración pendiente para prueba real
1. Crear proyecto Firebase y registrar Android com.alfaroute.gps.
2. Configurar google-services.json público del proyecto en el build Android y plugin Google Services (el proyecto native android está conservado; no ejecutar prebuild --clean sin revisar cambios nativos de voz/GPS).
3. Cargar credencial FCM v1 de servicio de Firebase en el proyecto Expo existente mediante la interfaz segura, nunca en Git ni chat. Configurar android.googleServicesFile en app.json al disponer del archivo.
4. Registrar expo-notifications mediante prebuild selectivo o configuración nativa equivalente, preservar servicio de voz. Instalar nuevo APK físico; exportación Metro no prueba compilación Gradle ni FCM.
5. Con respaldo y autorización, desplegar Rails y migraciones; activar KAYAK_REPORT_PUSH_ENABLED al terminar credenciales, verificar scheduler y acuses.
6. Prueba con dos cuentas del mismo equipo, otra de equipo distinto, pantalla bloqueada, app cerrada, aviso vencido y sesión revocada. No se envían avisos reales en las pruebas automatizadas.
