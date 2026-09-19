# Secret Gallery HD — Contexto y control del proyecto

Última actualización: 2026-09-18.
Estado: aplicación existente en desarrollo; revisión técnica inicial realizada.
Destinatarios: desarrolladores, responsables del proyecto y asistentes como Codex o Claude.

> Lee este documento antes de iniciar una actividad. Es una fotografía del proyecto, no una garantía de que todo funcione. Confirma los datos contra el código y actualiza esta guía al cerrar cambios relevantes. Los pendientes son propuestas; no constituyen autorización para ejecutarlos todos.

## 1. Objetivo

Secret Gallery HD es una aplicación de galería privada para importar, proteger, organizar y visualizar fotos y videos. Incluye control de acceso, una bóveda local cifrada, papelera y respaldos transferibles.

La implementación está enfocada principalmente en Android. Existen directorios para iOS, Windows, macOS, Linux y web, pero su presencia no implica soporte funcional comprobado. Hay código que usa dart:io y rutas específicas de Android.

## 2. Inicio de una nueva sesión

1. Leer esta guía y las instrucciones aplicables del repositorio, si existen, como AGENTS.md o CLAUDE.md.
2. Ejecutar `git status --short` y revisar el diff antes de editar. Conservar el trabajo local existente.
3. Identificar la actividad solicitada, los archivos afectados y sus criterios de aceptación.
4. Revisar el código actual: no asumir que los hallazgos de esta guía siguen pendientes.
5. Registrar la actividad y ejecutar las validaciones pertinentes.
6. Al terminar, actualizar los pendientes y la bitácora con cambios, resultados y limitaciones.

No introducir claves AES, PIN, contraseñas, contenido privado ni respaldos reales en la documentación, los logs, los tests o Git. Usar archivos de prueba descartables para validar borrados y restauraciones.

## 3. Tecnología y configuración

| Elemento | Estado observado |
| --- | --- |
| Framework / lenguaje | Flutter / Dart |
| Nombre del paquete | `secret_gallery` |
| Versión declarada | `1.0.0+1` |
| Restricción de Dart | `>=3.3.4 <4.0.0` |
| Persistencia | SQLite mediante sqflite y archivos locales |
| Credenciales y preferencias | flutter_secure_storage |
| Cifrado | encrypt y pointycastle |
| Estado de UI | StatefulWidget, setState y servicios singleton; tema con AnimatedBuilder |
| Lints | flutter_lints, configurado en analysis_options.yaml |

Dependencias principales por función:

- Galería y permisos: photo_manager, permission_handler.
- Archivos y base de datos: sqflite, path_provider, path.
- Seguridad: flutter_secure_storage, encrypt, pointycastle, local_auth.
- Video: video_player, chewie, video_thumbnail.
- Cámara: camera.
- Respaldos y compartir: archive, file_picker, share_plus.
- Presentación: google_fonts, flutter_staggered_grid_view, pinput y otros componentes.
- Pantalla: wakelock_plus, screen_brightness.

Consultar `pubspec.yaml` para las restricciones declaradas y `pubspec.lock` para las versiones resueltas. No actualizar dependencias en bloque sin revisar compatibilidad y validar los flujos afectados.

## 4. Mapa del código

| Ruta | Responsabilidad |
| --- | --- |
| `lib/main.dart` | Inicio, tema, AppEntry, elección de pantalla de acceso y ciclo de vida |
| `lib/app/app.dart` | Archivo vacío al momento de la revisión; no es el punto de entrada |
| `lib/core/database/db_helper.dart` | Esquema SQLite, carpetas, fotos, papelera e intrusos |
| `lib/core/security/crypto_service.dart` | Generación y almacenamiento de clave AES; cifrado de archivos |
| `lib/core/security/pin_service.dart` | Guardado y validación de PIN |
| `lib/core/security/password_service.dart` | Guardado y validación de contraseña |
| `lib/core/security/biometric_service.dart` | Autenticación biométrica |
| `lib/core/security/intruder_service.dart` | Captura de intrusos |
| `lib/core/services/media_service.dart` | Importación, descifrado, cachés, exportación y eliminación de medios |
| `lib/core/services/backup_service.dart` | Exportación y restauración de respaldos |
| `lib/core/services/lifecycle_guard.dart` | Supresión temporal del bloqueo/cierre durante acciones externas |
| `lib/core/services/prefs_service.dart` | Preferencias y método de acceso |
| `lib/core/services/theme_service.dart` | Carga y aplicación del tema |
| `lib/core/services/security_channel.dart` | Canal Flutter hacia protección nativa de pantalla |
| `lib/core/theme/app_colors.dart` | Colores de la aplicación |
| `lib/features/albums/` | Pantallas de carpetas y subcarpetas |
| `lib/features/photos/` | Cuadrícula, visor de fotos y reproductor de video |
| `lib/features/import/` | Selección de medios desde la galería |
| `lib/features/lock/` | PIN, contraseña, biometría y selección del método |
| `lib/features/camouflage/` | Calculadora de camuflaje |
| `lib/features/backup/` | UI de exportación y restauración |
| `lib/features/trash/` | Papelera |
| `lib/features/intruders/` | Visualización de capturas de intrusos |
| `lib/features/settings/` | Configuración |
| `lib/shared/widgets/` | Miniaturas, selectores, árbol de carpetas y confirmaciones |
| `android/app/src/main/kotlin/com/example/secret_gallery/MainActivity.kt` | FlutterFragmentActivity y control de FLAG_SECURE |
| `test/` | Pruebas automatizadas; cobertura inicial muy limitada |

## 5. Funciones implementadas y flujos

### Acceso

`main()` inicializa Flutter, fija orientación vertical, carga el tema y ejecuta SecretGalleryApp. AppEntry consulta PIN y preferencias. El primer inicio crea un PIN de respaldo y después ofrece elegir método de acceso. Los métodos disponibles son PIN, contraseña y biometría; existe un modo de camuflaje con calculadora.

AppEntry observa el paso a segundo plano. Según la preferencia, termina el proceso o cambia el estado a bloqueado. LifecycleGuard suspende temporalmente ese comportamiento al compartir o seleccionar archivos externos. Este flujo necesita las correcciones y pruebas indicadas en los pendientes.

### Importación

Se solicita acceso a la galería, se seleccionan assets y MediaService delega a MediaTransferService, que procesa las transferencias mediante una cola exclusiva y elementos secuenciales. Cada archivo se cifra y se descifra para verificar su SHA-256 antes de registrar la copia en SQLite. Solo después se solicita borrar el original público; se comprueban los IDs que el sistema confirma como eliminados. Los resultados distinguen archivos importados, fallidos y originales públicos conservados. Secret vuelve a estar disponible para importar.

### Visualización y exportación

Los medios se descifran para visualización. Las fotos y miniaturas usan cachés en memoria. Los videos y sus miniaturas pueden requerir archivos temporales descifrados. La exportación usa un temporal privado y una única publicación por MediaStore hacia `DCIM/Secret` en Android 29+. En Android 28 o anterior, el canal nativo crea una copia pública y la registra mediante MediaScanner. Se verifica el contenido público antes de retirar el registro privado; el nombre de exportación y el ID público permiten reutilizar una publicación en los reintentos.

### Papelera y carpetas

La base de datos conserva carpetas, relaciones padre-hijo, portadas y registros de medios. La papelera mueve metadatos entre tablas. Hay operaciones de varios pasos sin transacción que requieren revisión.

## 6. Modelo de datos y formatos que deben preservarse

- Base de datos: `secret_gallery_v3.db`; versión actual del esquema: `3` (migración desde versiones anteriores incluida). El sufijo del nombre y la versión del esquema son conceptos distintos.
- Tablas: `folders`, `photos`, `trash`, `intruders`.
- `folders`: nombre, parent_id, cover_photo_path y fechas.
- `photos`: folder_id, original_name, encrypted_path, original_path, date_added, source_asset_id, source_digest, exported_asset_id y export_name. Los campos nuevos permiten identificar importaciones y reintentar exportaciones.
- `trash`: referencia original, carpeta, nombres/rutas, fecha de eliminación y tipo.
- `intruders`: encrypted_path y captured_at.
- `folder_id = 0` se utiliza para medios de la pantalla principal. Tenerlo en cuenta antes de añadir claves foráneas.
- Bóveda: directorio `.sg_vault` bajo el directorio de documentos de la aplicación.
- Archivo cifrado: nombre basado en timestamp y nombre original con sufijo `.enc`; contenido actual de 16 bytes de IV seguido del contenido cifrado.
- Clave AES: 32 bytes, guardada bajo `sg_aes_key` en almacenamiento seguro.
- El PIN y la contraseña se almacenan como valores recuperables dentro del almacenamiento seguro; no son hashes de verificación.
- Varias columnas guardan rutas absolutas. Cambiar de instalación requiere resolver esas rutas.

### Respaldo actual

Un `.sgbackup` es un ZIP que contiene:

- `secrets.enc`: PIN, contraseña, método de acceso y clave AES, cifrados mediante una clave derivada de la contraseña del respaldo.
- `vault.db`: copia de la base de datos, sin cifrado adicional.
- `files/`: archivos de la bóveda, normalmente ya cifrados.
- `meta.json`: fecha de exportación y cantidad de archivos.

La derivación implementada usa PBKDF2 con HMAC-SHA256, 100000 iteraciones, sal de 16 bytes y clave de 32 bytes. El contenedor de secretos guarda sal, IV y contenido cifrado. No confundir el cifrado de secretos con cifrado del ZIP completo: sus metadatos y la base son legibles sin la contraseña.

Cualquier modificación de claves, esquema o formato debe contemplar los datos existentes, migración y compatibilidad de lectura. No regenerar silenciosamente una clave como solución a un fallo de descifrado.

## 7. Entorno y comandos de trabajo

Requisitos generales: Git, Flutter con Dart compatible, dependencias del proyecto y herramientas de la plataforma objetivo. Para Android se necesita Android SDK y un emulador o dispositivo configurado.

```sh
# Contexto y herramientas
git status --short
git diff --stat
flutter --version
flutter doctor -v
flutter devices

# Preparación: instala las versiones resueltas cuando corresponda
flutter pub get

# Validación
flutter analyze
flutter test --no-pub

# Ejecución en un dispositivo disponible
flutter run -d <device-id>

# Compilación de depuración, cuando forme parte de la actividad
flutter build apk --debug
```

No presentar estos comandos como ejecutados si no se corrieron. Evitar `flutter clean` como primer paso rutinario: elimina artefactos y puede complicar la reproducción.

En la máquina de la revisión se encontraron Flutter en `C:\src\flutter` y Git en `C:\Program Files\Git\cmd\git.exe`. Git no estaba disponible inicialmente en PATH. Estas rutas son locales, no requisitos del repositorio. El entorno de revisión tenía permisos de solo lectura y necesitó autorización para que el analizador y las pruebas escribieran su configuración y temporales.

## 8. Validación de referencia — 2026-09-18

| Validación | Resultado |
| --- | --- |
| `dart analyze --no-fatal-warnings` | 0 errores, 8 advertencias y 85 observaciones informativas; 93 en total |
| `flutter test --no-pub` | 1 prueba aprobada |
| Compilación de APK | No realizada en la revisión |
| Prueba funcional en dispositivo | No realizada en la revisión |
| Cámara, biometría y permisos reales | No verificados en dispositivo |
| Restauración entre instalaciones | No verificada mediante ejecución |

La única prueba efectiva estaba en `test/media_service_test.dart` y verifica filtros para excluir la carpeta de exportación de la galería. `test/widget_test.dart` contenía un main vacío. La aprobación de esa prueba no valida la seguridad ni la integridad de la bóveda.

Entre las advertencias hay manejadores catchError que no devuelven el tipo esperado, código sin uso y operaciones nulas redundantes. Las observaciones incluyen APIs obsoletas y uso de BuildContext después de esperas asíncronas.

## 9. Pendientes priorizados

Estado inicial de todos los elementos: pendiente. Los hallazgos provienen de inspección del código, salvo los resultados del analizador y tests. La prioridad expresa impacto potencial; no significa que se haya reproducido una pérdida de datos.

| ID | Prioridad | Hallazgo / actividad | Archivos principales | Criterio de cierre |
| --- | --- | --- | --- | --- |
| SG-001 | P0 | Posible carrera al crear la primera clave: varias importaciones leen una clave ausente y pueden generar claves distintas | crypto_service.dart, media_service.dart | Inicialización única incluso entre consumidores concurrentes; importar varios medios en instalación nueva y descifrarlos tras reiniciar |
| SG-002 | P0 | Bloqueo cambia AppEntry pero no elimina ni cubre necesariamente las rutas superiores del Navigator | main.dart y navegación de features | Ningún visor, carpeta o ajuste sensible queda accesible al volver de segundo plano sin autenticar |
| SG-003 | P0 | Restauración reemplaza DB y borra la bóveda antes de terminar; no hay rollback ni validación completa previa | backup_service.dart | Validar primero, restaurar en área temporal y preservar la bóveda anterior ante archivos corruptos, incompletos o fallos de escritura |
| SG-004 | P1 | Respaldos mantienen rutas absolutas de la instalación original | backup_service.dart, db_helper.dart | Restaurar en otra ubicación y abrir medios, portadas, papelera y capturas correctamente |
| SG-005 | P1 | Borrado de carpetas elimina archivos recursivamente pero no limpia explícitamente todos los registros relacionados; no se configura la activación de foreign_keys | db_helper.dart, media_service.dart | Borrar árbol de prueba sin registros huérfanos; preservar medios ajenos y contemplar la papelera |
| SG-006 | P1 | Extracción de files/ une nombres del ZIP a la ruta local sin comprobar que permanezcan dentro de la bóveda | backup_service.dart | Rechazar rutas que escapen del directorio destino antes de modificar datos |
| SG-007 | P1 | Base y metadatos del respaldo son legibles; los formatos no incluyen autenticación explícita de integridad | crypto_service.dart, backup_service.dart | Definir formato versionado con confidencialidad e integridad adecuadas y estrategia de migración compatible |
| SG-008 | P1 | Onboarding deja _choosingMethod activo y AppEntry no recarga el método elegido al completar o cambiar ajustes | main.dart, access_method_screen.dart | Tras configurar o cambiar acceso, el siguiente bloqueo usa el método correcto sin repetir onboarding |
| SG-009 | P1 | Importación/exportación capturan errores parciales y pueden mostrar finalización sin resultados detallados | media_service.dart, gallery_picker_screen.dart, unlock_helper.dart | Informar éxitos y fallos por lote; verificar destino antes de eliminar origen; probar cancelación y falta de espacio |
| SG-010 | P2 | Fotos completas en caché, videos y respaldos cargados en memoria; temporales descifrados requieren limpieza robusta | media_service.dart, video_player_screen.dart, backup_service.dart | Medir con archivos grandes; limitar memoria y limpiar temporales también ante errores |
| SG-011 | P2 | Operaciones de papelera de varios pasos sin transacción y movimientos de carpetas sin validación central contra ciclos | db_helper.dart, folder_tree_sheet.dart | Consistencia ante errores y rechazo de mover una carpeta dentro de sus descendientes |
| SG-012 | P2 | Configuración Android duplicada/anidada; applicationId de ejemplo y release con firma debug | android/app/build.gradle | Unificar configuración y definir identidad/firma para distribución cuando corresponda |
| SG-013 | P2 | Compatibilidad fuera de Android incompleta; Info.plist no declara permisos de fototeca | ios/Runner/Info.plist, media_service.dart | Definir plataformas soportadas y validar sus permisos, almacenamiento y flujos |
| SG-014 | P2 | Cobertura mínima, README genérico y advertencias pendientes | test/, README.md, analysis_options.yaml | Documentar arranque, añadir pruebas de los flujos críticos y corregir advertencias sin ocultarlas globalmente |

P0: atender primero por riesgo para privacidad o datos. P1: siguiente bloque de confiabilidad y seguridad. P2: mantenimiento, rendimiento y preparación de plataformas/distribución.

Orden sugerido: SG-001 y SG-002; después SG-003/004/006 como bloque de restauración; luego integridad de carpetas y operaciones de medios. Mantener compatibilidad de datos durante cada etapa.

## 10. Estado de Git observado al iniciar la documentación

Último commit observado: `80b5f48` — `Changes in security backup photos`.

Ya existían modificaciones locales en:

- `lib/core/services/media_service.dart`
- `lib/features/albums/albums_screen.dart`
- `lib/features/albums/folder_detail_screen.dart`
- `lib/features/import/gallery_picker_screen.dart`
- `lib/features/photos/photo_viewer_screen.dart`
- `lib/shared/widgets/folder_thumbnail.dart`
- `lib/shared/widgets/photo_thumbnail.dart`
- `lib/shared/widgets/unlock_helper.dart`

También figuraban sin seguimiento `.claude/`, `devtools_options.yaml` y `test/media_service_test.dart`. Esta lista es histórica: ejecutar git status al comenzar cada sesión. No atribuir estos cambios a una sesión nueva ni revertirlos automáticamente.

## 11. Organización y cierre de actividades

Mantener actividades pequeñas y comprobables. Si se cambia UI, revisar su comportamiento visual. Si se cambia almacenamiento, seguridad o restauración, añadir pruebas que detecten fallos reales, incluyendo errores parciales y reapertura de datos.

Una actividad puede marcarse terminada cuando:

- Cumple su alcance y criterios de aceptación.
- Los cambios se revisaron mediante diff y se preservó el trabajo previo.
- Se ejecutaron las validaciones pertinentes y se registraron sus resultados reales.
- Se documentaron las limitaciones pendientes, especialmente las pruebas que requieren dispositivo.
- Se actualizó este documento si cambió arquitectura, formato, configuración o estado de un pendiente.

No asumir que una tarea requiere publicar, hacer push, distribuir APK o modificar datos privados. Esas acciones dependen del alcance solicitado.

### Plantilla de actividad

```md
### ACT-XXX — Título
- Fecha:
- Responsable / sesión:
- Estado: pendiente | en curso | bloqueada | terminada
- Objetivo y alcance:
- Pendientes relacionados: SG-XXX
- Archivos afectados:
- Criterios de aceptación:
- Cambios realizados:
- Validación ejecutada y resultado:
- Compatibilidad / migración de datos:
- Limitaciones o bloqueos:
- Siguiente paso:
- Commit / PR, si existe:
```

### Bitácora

| Fecha | Actividad | Resultado | Siguiente paso |
| --- | --- | --- | --- |
| 2026-09-18 | Revisión inicial del proyecto | Arquitectura y riesgos revisados; análisis con 93 observaciones y una prueba aprobada; sin cambios funcionales | Elegir una actividad del backlog |
| 2026-09-18 | Creación de esta guía | Contexto, formatos, comandos, backlog y proceso de continuidad documentados | Mantener la guía al cerrar actividades |

## 12. Mensaje sugerido para retomar el proyecto

> Lee CONTEXTO_PROYECTO.md y las instrucciones aplicables del repositorio. Revisa el estado actual de Git y conserva los cambios existentes. La actividad de esta sesión es: [describir]. Confirma los hallazgos relevantes contra el código, implementa el alcance solicitado, ejecuta las validaciones pertinentes y actualiza la actividad y la bitácora con resultados y pendientes. No marques como probados los flujos que no ejecutaste.

## 13. ACT-001 — Desbloquear y volver a ocultar desde Secret

- Fecha: 2026-09-18.
- Estado: cambios implementados; comprobación funcional en teléfono pendiente.
- Alcance: publicación única, reimportación desde Secret, selección múltiple, verificación antes de borrar y manejo de errores/reintentos.
- Causa encontrada en código: unlockPhotos escribía primero un archivo público en DCIM/Secret y luego llamaba a saveImageWithPath/saveVideo. La implementación instalada de photo_manager 3.9.0 realiza una inserción en MediaStore y, en Android 29+, copia el archivo. Se eliminó la escritura pública previa. La diferencia exacta entre las vistas de ambas galerías no se reprodujo en un teléfono.
- La UI ya deduplicaba por asset ID. No se encontraron listeners que añadieran manualmente otra copia a la lista; el problema de escritura no se solucionaba con ese filtro.
- El álbum Secret y sus medios estaban excluidos deliberadamente por filtros. Se retiraron esas exclusiones y el selector ahora ofrece Ocultar.

### Archivos de esta actividad

| Archivo | Cambio |
| --- | --- |
| `lib/core/services/media_service.dart` | Elimina filtros de Secret y escritura pública duplicada; delega transferencias y permisos; deduplica lecturas por asset ID |
| `lib/core/services/media_transfer_service.dart` | Nuevo coordinador de importación/exportación; cola exclusiva, SHA-256, resultados parciales y reintentos |
| `lib/core/services/device_gallery.dart` | Adaptador de photo_manager, permisos, búsqueda de exportaciones y compatibilidad Android |
| `lib/core/security/crypto_service.dart` | Inicialización compartida de clave entre instancias; nombres cifrados únicos y escritura con flush |
| `lib/core/database/db_helper.dart` | Esquema 3, identidad de importación, nombre/ID de exportación y retiro transaccional de registros/portadas |
| `lib/features/import/gallery_picker_screen.dart` | Acción Ocultar, refresco de álbumes y cachés, descarte de cargas obsoletas, errores y resultados reales |
| `lib/shared/widgets/unlock_helper.dart` | Evita diálogos simultáneos; cierra el progreso al fallar e informa resultados reales |
| `android/app/src/main/kotlin/com/example/secret_gallery/MainActivity.kt` | Canal de versión Android y publicación mediante copia + escaneo para Android <=28 |
| `test/media_service_test.dart` | Regresiones del ciclo completo, cancelaciones, fallos e interrupciones |
| `test/crypto_service_test.dart` | Verifica cifrado concurrente con una única clave persistida |
| `CONTEXTO_PROYECTO.md` | Actualización del flujo, esquema y registro de esta actividad |

### Seguridad y reintentos

- Ocultar: leer original → cifrar → descifrar y comparar SHA-256 → registrar → volver a comprobar origen → solicitar borrado → comprobar IDs eliminados.
- Si se cancela el borrado público, se conserva la copia privada verificada y se informa que el original sigue público. Un reintento con el mismo asset ID y contenido reutiliza la copia privada.
- Desbloquear: persistir nombre público único → publicar una vez desde temporal privado → persistir ID público → verificar SHA-256 → retirar registro privado y limpiar archivo cifrado.
- Los nombres públicos incorporan un identificador para recuperar una publicación interrumpida; no se deduplican fotografías distintas por compartir nombre.
- No se borran automáticamente archivos o registros duplicados producidos por versiones anteriores: su identidad debe verificarse en el dispositivo antes de cualquier limpieza.
- Si una exportación previa existe pero no puede leerse o verificarse, se conserva la copia privada y se informa fallo.
- Android moderno utiliza almacenamiento por MediaStore; el permiso de escritura de almacenamiento se solicita únicamente para Android antiguo. Las confirmaciones externas usan LifecycleGuard.

### Validación realizada antes de pedir reducir pruebas

- 20 pruebas automatizadas aprobadas: lotes de 1/4/10, ciclo ocultar/desbloquear/ocultar, selección repetida, concurrencia, cancelación del borrado, fallos de escritura/verificación/DB, reintentos tras reinicio, video y clave compartida.
- Se compiló correctamente un APK de depuración durante la implementación. No equivale a una prueba funcional en teléfono.
- A solicitud del usuario, no se amplió la batería de pruebas. Los últimos ajustes menores y el resultado de las verificaciones que ya estuvieran en curso se deben distinguir de las pruebas previas.
- No se ejecutaron pruebas funcionales con fotos reales ni se instaló el APK en un dispositivo.

### Pendientes de aceptación en dispositivo (no ejecutados)

1. Con medios descartables, probar lotes de 1, 4 y 10: contar en Secret dentro del selector y en la galería nativa.
2. Volver a ocultarlos desde Secret y comprobar su desaparición pública después de autorizar el borrado.
3. Cancelar el permiso de eliminación y reintentar: una sola copia privada por asset.
4. Probar Android <=28, Android 29+ y acceso limitado a fotos donde esté disponible.
5. Abrir una instalación con DB anterior para comprobar la migración conservando sus medios.

SG-001 tiene corrección implementada y prueba de concurrencia aprobada. SG-009 tiene corrección implementada en este flujo; falta aceptación en dispositivo. Los demás pendientes conservan su estado salvo evidencia nueva.
## 14. ACT-002 — Quitar mensajes de éxito de las transferencias

- Fecha: 2026-09-18.
- El usuario confirmó que el flujo de ocultar/desbloquear ya funciona.
- Se eliminó el diálogo de resultados «Ocultar archivos» y el aviso de restauración exitosa. Al completar correctamente, la navegación y el refresco continúan sin confirmación adicional.
- Se conservan los avisos de errores, originales públicos retenidos y problemas de limpieza, así como la confirmación previa al desbloqueo y los indicadores de progreso.
- Archivos: `lib/features/import/gallery_picker_screen.dart` y `lib/shared/widgets/unlock_helper.dart`.
- No se cambió la lógica de transferencia ni se ejecutaron pruebas adicionales para este ajuste de presentación.
## 15. ACT-003 — Fluidez al ocultar y desbloquear

- Se detectaron búsquedas completas de la galería por cada exportación nueva, trabajo AES/SHA-256 en el isolate de UI y una recarga del álbum justo antes de cerrar el selector.
- Las exportaciones nuevas no buscan por nombre en toda la galería; la búsqueda se conserva para recuperar exportaciones interrumpidas con un nombre ya persistido.
- El cifrado, descifrado y hashes se ejecutan en isolates de trabajo con compute. Los plugins y la coordinación permanecen en el isolate principal.
- Cada operación permite como máximo dos fotos simultáneas; los videos se procesan solos. La cola exterior sigue evitando solapamiento entre operaciones del usuario.
- Se evita recargar el álbum público al terminar una importación que cierra el selector. La galería privada sigue actualizándose mediante el resultado de navegación existente.
- Se conservan la verificación de contenido, el registro previo al borrado, los reintentos y la ausencia de mensajes de éxito.
- Archivos: crypto_service.dart, media_transfer_service.dart y gallery_picker_screen.dart.
- No se midieron tiempos en un teléfono; la mejora numérica debe confirmarse en dispositivo. No se solicita una compilación completa ni pruebas prolongadas para este ajuste.
## 16. ACT-004 — Carga progresiva de miniaturas al desplazar

- La cuadrícula ya usaba GridView.builder; el cuello de botella encontrado era cargar originales completos para miniaturas, retener hasta 200 originales y lanzar muchas cargas sin límite.
- Nuevo ThumbnailCache: hasta dos trabajos simultáneos, solicitudes compartidas por ruta, prioridad para solicitudes recientes y descarte de solicitudes de celdas desmontadas. Caché LRU de miniaturas limitada a 24 MiB y 180 entradas; no escribe fotos de previsualización sin cifrar en disco.
- Fotos reducidas conservando proporciones, a un máximo de 512 px por lado. El visor sigue solicitando originales; su caché ahora tiene límites de 32 MiB y cuatro entradas.
- Las celdas y portadas posponen cargas durante desplazamientos rápidos mediante Scrollable.recommendDeferredLoadingForContext, cancelan solicitudes obsoletas y no cargan si la previsualización está desactivada.
- Las miniaturas de video comparten la cola y usan temporales exclusivos con limpieza final. El selector de portada y la papelera también solicitan miniaturas pequeñas.
- Se conservan los originales, el cifrado, las transferencias y la selección. Los límites citados corresponden a las cachés propias; Flutter y el procesamiento en curso también consumen memoria.
- Pendiente medir FPS y memoria en teléfono con más de 150 fotos. No se afirma una tasa de cuadros ni un tiempo de carga medido.
## 17. ACT-005 — Reducir esperas durante el desbloqueo

- CryptoService.prepareExportFile une descifrado, SHA-256 y escritura del temporal privado en un único worker. Solo devuelve la huella; evita devolver el original completo al isolate de UI y copiarlo otra vez para calcular el hash.
- El desbloqueo mantiene dos puestos de trabajo para fotos y ocupa el siguiente en cuanto se libera uno, sin barreras entre parejas. Los videos siguen procesándose individualmente.
- DeviceGallery reutiliza la versión Android consultada en vez de pedirla por cada archivo.
- Se mantienen publicación única, recuperación de reintentos, comprobación del contenido público antes de retirar el registro privado y limpieza de temporales. No se añadieron mensajes de éxito.
- El doble de pruebas existente se adaptó a la nueva API; no se ejecutó una batería larga ni se recompiló el APK. Mejora de tiempo pendiente de medir en teléfono.
- Archivos: crypto_service.dart, media_transfer_service.dart, device_gallery.dart, test/media_service_test.dart y esta guía.