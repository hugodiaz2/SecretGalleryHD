# Revisión de fallos — Secret Gallery HD

Fecha: 2026-09-21. Revisión de código y pruebas locales con datos sintéticos. No es una certificación de seguridad ni una validación en teléfonos reales.

## Fallos corregidos

| Riesgo | Hallazgo | Corrección |
| --- | --- | --- |
| Alto | Una pantalla abierta sobre AppEntry podía seguir visible después del bloqueo | Al pasar a segundo plano se cierran las rutas privadas, se limpian miniaturas y se bloquea antes de leer preferencias. |
| Alto | Un error de almacenamiento se interpretaba como primera instalación; el plugin podía borrar credenciales automáticamente | Inicio con error recuperable, sin configurar otro PIN sobre una bóveda existente. resetOnError desactivado. La clave AES no se regenera si existen archivos cifrados. |
| Alto | Restaurar reemplazaba la base y eliminaba archivos antes de validar el respaldo | Extracción en staging, validación de claves, base SQLite y archivos referenciados antes de instalar. Copia anterior y registro en almacenamiento seguro para rollback y recuperación al siguiente inicio. |
| Alto | Rutas de un ZIP podían salir del destino o repetir archivos | Rechazo de rutas absolutas, traversal, subdirectorios inesperados y entradas duplicadas antes de modificar la bóveda. |
| Alto | Las rutas absolutas del dispositivo original rompían respaldos en otro teléfono | Remapeo de fotos, portadas, papelera, capturas y contenido de carpetas archivadas a la ruta actual. |
| Medio | Exportar respaldo retenía todos los videos en RAM y comprimía en el hilo principal | Escritura a archivo desde un worker, entradas de medios sin recomprimir; copia de SQLite después de cerrar la conexión. |
| Medio | Enviar/restaurar una foto en papelera podía quedar a medias o duplicarse por doble toque | Transacciones y relectura del registro. Esquema 5 con photo_payload conserva fechas y recibos de transferencia. |
| Medio | El onboarding podía reaparecer y usar un método de acceso desactualizado | Se termina la elección de método al entrar y se actualizan método/camuflaje al bloquear. |
| Medio | Un video que fallaba al inicializar retenía controladores al reintentar | Liberación de reproductores y temporal en la ruta de error. |
| Medio | Se podía salir de la pantalla de respaldo y operar sobre datos que se estaban reemplazando | Bloqueo de retroceso en la pantalla ocupada, exclusión entre respaldos y transferencias activas o en cola, y capa que bloquea interacción durante el proceso. |

## Comprobaciones realizadas

27 pruebas automatizadas aprobadas: siete comprobaciones nuevas y veinte existentes. Incluyen rechazo de respaldos incompletos y rutas inválidas sin tocar archivos privados, clave ausente, remapeo de rutas, cola de miniaturas, concurrencia y fallos de importación/exportación. Usan archivos sintéticos, no fotos del usuario.

Análisis Dart de los archivos principales sin errores; quedan avisos de estilo y APIs obsoletas. No se ha simulado todavía una restauración completa mediante SQLite real ni un cierre del proceso Android entre cada paso del rollback. Las pruebas de validación no sustituyen esas comprobaciones.

APK release compilada correctamente el 2026-09-21 mediante flutter build apk --release --no-pub (58.3 MB), incluyendo la exclusión entre transferencias y respaldos. No instalada en un teléfono durante esta revisión.

## Pendientes antes de considerar la app lista para publicar

1. **Alta prioridad: formato de respaldo y cifrado autenticado (SG-007).** El ZIP aún contiene la base de datos y metadatos legibles. Los secretos y archivos están cifrados, pero el formato heredado no autentica todo el contenido. Se necesita un formato versionado con integridad criptográfica y lectura compatible de respaldos antiguos. No describir el ZIP completo como cifrado ni prometer seguridad absoluta.
2. **Pruebas de aceptación Android.** Con archivos descartables: importar/desbloquear videos grandes en dos teléfonos; bloquear desde visor, subcarpeta y ajustes; restaurar una carpeta con varios niveles; probar respaldo entre instalaciones; simular falta de espacio y cierre durante la instalación/restauración. Confirmar que se recupera la bóveda anterior al reiniciar.
3. **Respaldos antiguos comprimidos.** Aunque se evita cargar todo el ZIP de una vez, la librería puede descomprimir una entrada antigua completa en memoria. Medir respaldos con videos grandes. El nuevo exportador guarda medios sin recomprimir.
4. **Previsualizaciones grandes.** El límite preventivo de lectura en memoria de 32 MiB puede dejar sin vista previa una foto muy grande. Transferencia por bloques disponible; mejora pendiente para generar miniaturas sin cargar ese original completo.
5. **Firma y distribución.** El proyecto todavía usa firma de depuración en release. Hace falta configuración de publicación y revisión de permisos/política de privacidad antes de Play Store.

No se modificó el formato de los archivos privados ni se recifraron fotos existentes. No se ejecutaron borrados ni restauraciones sobre la bóveda de un dispositivo del usuario.