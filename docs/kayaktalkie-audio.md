# Audio: almacenamiento y limite de retencion

Requisito del usuario: cualquier audio temporal que llegue a almacenarse tendra
una vida maxima de una hora desde su captura. No mantener historiales indefinidos.

Verificacion actual:
- Codigo propio de Rails, web y movil: no se encontraron llamadas para grabar
  archivos de audio ni iniciar LiveKit Egress. Los microfonos publican pistas
  para reproduccion en vivo.
- LiveKit Cloud / KayakTalkie&GPS / Egresses / Past 7 days: No results.
  Esta evidencia se limita al periodo mostrado; no demuestra una auditoria
  de todos los sistemas internos del proveedor.
- Las tablas de turnos, sesiones y colas guardan metadatos; no contienen audio.

Comportamiento que debe conservar esta publicacion:
- Voz en vivo, sin grabaciones ni historial reproducible.
- Los buffers de transmision/reproduccion son transitorios y los gestiona WebRTC;
  no son archivos guardados durante una hora ni un archivo de conversaciones.
- La hora es un limite maximo para un futuro audio temporal persistido, no una
  orden de empezar a grabar o de mantener buffers por una hora.

Si se incorpora almacenamiento temporal en el futuro, su implementacion debera:
- establecer expires_at = captured_at + 1.hour y no ampliar esa caducidad al leer;
- impedir acceso/reproduccion al alcanzar la fecha de caducidad;
- eliminar los objetos y archivos temporales automaticamente, con reintentos;
- aplicar la misma regla a cache, versiones y copias; no incluirlos en respaldos
  de larga retencion ni logs;
- verificar la regla en almacenamiento real antes de activar la funcionalidad.

No se ha agregado una tarea ficticia de borrado: actualmente no existe un
repositorio de audio al que aplicarla. Tampoco se modifico la retencion de los
respaldos de Roll de Guias, que contienen datos de gestion, no grabaciones.
No se desplego ningun cambio en este paso.
