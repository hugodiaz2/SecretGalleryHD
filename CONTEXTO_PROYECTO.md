# Secret Gallery HD — Contexto y control del proyecto

Última actualización: 2026-09-20.
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
## 18. ACT-006 — Motor Android para transferencias más rápidas (2026-09-20)

- Motivo: las optimizaciones previas reducían bloqueos de interfaz, pero AES y SHA-256 seguían ejecutándose en Dart y generando buffers completos por archivo.
- Android ahora usa VaultCrypto (Java/JCA) a través de VaultCryptoPlugin, con dos trabajadores fuera del hilo principal. Cifrado, descifrado de exportación y SHA-256 leen bloques de 128 KiB; no cargan fotos o videos completos en el puente Flutter.
- Se conserva el formato existente: IV de 16 bytes seguido de AES-SIC/CTR con relleno PKCS7, clave de 256 bits. No cambia la clave, no se recifran ni migran los archivos existentes y no se introduce un nuevo formato. Esta optimización no añade autenticación criptográfica; SG-007 continúa pendiente.
- La verificación al ocultar descifra y calcula SHA-256 en el motor nativo, sin devolver el contenido completo a Dart. El borrado público sigue requiriendo que la copia privada haya sido verificada y registrada. El desbloqueo también conserva la verificación pública antes de retirar la privada.
- La escritura privada usa flush + fsync. Los destinos existentes no se sobrescriben; los archivos parciales nuevos se eliminan si la operación falla. El puente solo permite destinos dentro del almacenamiento de la aplicación.
- Otras plataformas y las previsualizaciones conservan los workers Dart existentes. Los permisos se siguen gestionando con photo_manager. No se cambiaron los mensajes de la interfaz.

### Comprobación puntual realizada

- Nueve vectores sintéticos generados por la librería Dart instalada: tamaños 1, 15, 16, 17, 31, 131071, 131072, 131073 y 1048576 bytes; IV elegido para comprobar el acarreo del contador.
- El motor Java genera exactamente los mismos bytes cifrados que Dart y descifra correctamente los archivos producidos por Dart. Se verificaron también SHA-256, modo solo verificación, rechazo de sobrescritura, truncamiento, padding inválido y limpieza de salida parcial.
- El encoder Dart existente no admite entrada vacía; no se considera una fotografía válida y no forma parte de los vectores de compatibilidad.
- Comprobación ejecutada con el JDK local; no equivale a un benchmark ni a una validación funcional en un teléfono Android.
- Análisis Dart de los servicios modificados: sin errores; observaciones de estilo pendientes.

### Archivos y reproducción

- `android/app/src/main/kotlin/com/example/secret_gallery/VaultCrypto.java`: motor por bloques, sin dependencia de APIs Android para permitir comprobación JVM.
- `android/app/src/main/kotlin/com/example/secret_gallery/VaultCryptoPlugin.kt`: puente Android y ejecución en segundo plano.
- `MainActivity.kt`: registro del plugin.
- `lib/core/security/crypto_service.dart`: selección del motor nativo Android y respaldo Dart para otras plataformas.
- `lib/core/services/media_transfer_service.dart`: verificación privada mediante digest, sin transportar todo el archivo a Dart.
- `tool/crypto_compatibility.dart` y `android/app/src/test/java/com/example/secret_gallery/VaultCryptoCompatibilityCheck.java`: comprobación reproducible con archivos de prueba.

```sh
dart run tool/crypto_compatibility.dart build/crypto_compatibility
javac -encoding UTF-8 -d build/crypto_compatibility/classes android/app/src/main/kotlin/com/example/secret_gallery/VaultCrypto.java android/app/src/test/java/com/example/secret_gallery/VaultCryptoCompatibilityCheck.java
java -cp build/crypto_compatibility/classes com.example.secret_gallery.VaultCryptoCompatibilityCheck build/crypto_compatibility
```

Para medir la rapidez real, usar una compilación release y el mismo lote de fotografías en el mismo teléfono. Registrar cantidad, tamaño total y duración de ocultar/desbloquear; no comparar una ejecución debug con aplicaciones release. Las esperas del permiso de borrado del sistema se registran aparte. No se promete un factor de aceleración sin esa medición.

El nuevo canal Android requiere reconstruir e instalar la aplicación; hot reload por sí solo no lo activa. No desinstalar ni borrar datos de la bóveda para actualizar.

### Resultado de compilación ACT-006

- 2026-09-20: "flutter build apk --release --no-pub" completado correctamente, incluyendo compilación del motor Java, plugin Kotlin y empaquetado release.
- Artefacto: build/app/outputs/flutter-apk/app-release.apk (57.9 MB reportados por Flutter).
- No se instaló ni publicó automáticamente. Pendiente medición de tiempos en el teléfono del usuario.

## 19. ACT-007 — Respetar la barra de navegación del teléfono (2026-09-20)

- Se añadió SafeArea en el builder de MaterialApp, por encima del Navigator: protege pantallas y paneles modales (incluida la paleta de colores) frente a la barra inferior y las intrusiones laterales del sistema.
- El espacio se obtiene dinámicamente de MediaQuery; no se fija una altura según marca o modelo. Los SafeArea internos no duplican el margen consumido. El borde superior sigue a cargo de AppBar y de los SafeArea de cada pantalla.
- El fondo del área reservada usa el tema actual. Se conserva el tratamiento normal del teclado y los márgenes se actualizan al cambiar la visibilidad de las barras del sistema.
- Archivo: lib/main.dart. No cambia cifrado, importación ni desbloqueo. Pendiente comprobación visual en el teléfono con navegación por botones y por gestos; no se generó otro APK para este ajuste.
## 20. ACT-008 — Selector de álbumes compacto (2026-09-20)

- El selector de importación muestra tres columnas en lugar de dos, con proporción 0.90, separación de 6 y margen exterior de 10 píxeles lógicos, siguiendo la referencia visual del usuario.
- Pestañas FOTOS/VIDEOS de 44 píxeles lógicos, solo texto. Tarjetas con esquinas de 4, etiquetas y conteos más pequeños y menos relleno para mostrar más álbumes a la vez.
- Archivo: lib/features/import/gallery_picker_screen.dart. Conserva conteos, selección de álbumes, cuadrícula interna de fotos y videos y transferencias. Mantiene el SafeArea global de ACT-007.
- Revisión del diff; pendiente comprobación visual en dispositivo. No se compiló un APK para este ajuste de presentación.
## 21. ACT-009 — Lectura nativa para acelerar miniaturas (2026-09-20)

- CryptoService.decryptFile usa ahora decryptBytes del motor Java/JCA en Android. Antes, las miniaturas todavía descifraban originales con AES en un worker Dart. Otras plataformas conservan compute.
- El nuevo método reutiliza la comprobación PKCS7 de PlainSink y devuelve bytes en memoria, sin crear nuevos temporales descifrados. Sirve también a los consumidores existentes de decryptFile (visor y entrada para miniaturas de video); la publicación y el borrado no cambian.
- Las miniaturas de fotos pasan de 512 a 384 píxeles máximos por lado. Se conserva la resolución del original en el visor. Las celdas ajustan también su tamaño de decodificación a 384.
- Tras desplazamiento rápido, la comprobación de reanudación pasa de 80 a 32 ms. La caché sigue acotada a 24 MiB/180 entradas y la cola mantiene dos trabajos simultáneos para limitar presión de memoria. No se promete un multiplicador de velocidad sin medición en teléfono.
- La lectura de previsualización requiere el original comprimido completo en memoria; el procesamiento por bloques de las transferencias se conserva. No se crea caché persistente de fotos sin cifrar.
- Verificación JVM: nueve vectores Dart/Java con igualdad de bytes de la nueva lectura, límites de bloque y rechazo de padding inválido, correctos. Pendiente medir tiempos de carga y fluidez en Android.
- Requiere reconstruir e instalar con flutter run --release; hot reload no registra el método nativo nuevo. No se generó un APK para esta modificación.
## 22. ACT-010 — Menú para mover con cuadrícula y navegación (2026-09-20)

- FolderTreeSheet sustituye el árbol de filas por tarjetas compactas de carpetas, con columnas adaptadas al ancho (hasta seis; cinco en teléfonos de ancho suficiente).
- Se abre en la raíz. Tocar una tarjeta entra en esa carpeta y muestra sus hijos directos. El encabezado muestra la ruta, Regresar sube un nivel, Buscar permite encontrar carpetas de cualquier profundidad y Cancelar cierra el panel. El botón del sistema también retrocede dentro del selector.
- Mover aquí devuelve la carpeta abierta al llamador existente; entrar en una carpeta no ejecuta el movimiento. La carpeta actual se puede explorar, pero no confirmar como destino. Durante la búsqueda se debe abrir un resultado antes de confirmar.
- Las carpetas seleccionadas para mover y todos sus descendientes quedan excluidos, evitando ciclos. Se conserva la compatibilidad con llamadores que incluyen la carpeta actual entre las exclusiones.
- Se carga la jerarquía una vez y se indexa en memoria; se eliminaron las consultas de conteo por tarjeta. Incluye carga, error con reintento, estados vacíos, ajuste al teclado y colores del tema.
- El selector compartido actualiza los flujos de mover fotos, videos y carpetas. No cambia las operaciones de cifrado ni transferencia.
- Análisis Dart del archivo sin incidencias. Pendiente comprobación visual en dispositivo; no se generó otro APK.
## 23. ACT-011 — Portadas en la cuadrícula de destinos (2026-09-20)

- Las tarjetas de FolderTreeSheet muestran la portada de cada carpeta usando la misma resolución de portada de la galería: portada manual, archivo directo más reciente o portada de una subcarpeta.
- Si no existe portada, está cargando o no puede leerse, se conserva el icono de carpeta. Las portadas de video usan miniaturas.
- Reutiliza la caché compartida de miniaturas, limita la decodificación a 384 px y pospone el trabajo durante desplazamientos rápidos. Memoriza las consultas de portada durante la vida del panel y descarta cargas pendientes de celdas desmontadas.
- No modifica navegación, búsqueda ni confirmación de destino. Análisis Dart del selector sin incidencias; pendiente revisión visual en teléfono.
## 24. ACT-012 — Barra de acciones del visor sobre la navegación (2026-09-20)

- El visor de fotos abre en edgeToEdge con los controles visibles; usa immersiveSticky únicamente cuando el usuario oculta las barras al tocar la imagen. Al mostrarlas, restaura edgeToEdge.
- Compartir/Mover/Desbloquear/Eliminar/Información pasan del Stack superpuesto al bottomNavigationBar del Scaffold, reservando espacio fuera de la foto y conservando SafeArea junto con la protección global.
- Los cinco botones distribuyen el ancho disponible con Expanded y etiquetas de hasta dos líneas para teléfonos estrechos.
- El visor de video también abre con navegación visible y restaura las barras al salir del modo de pantalla completa de Chewie.
- No se modifican las operaciones de compartir, mover, desbloquear o eliminar. Pendiente comprobación visual en teléfono con navegación por botones y gestos.
## 25. ACT-013 — Mover fotos y subcarpetas a Inicio (2026-09-20)

- El nivel raíz de FolderTreeSheet ahora es un destino confirmable llamado Inicio, con el botón Mover a Inicio cuando el elemento viene de una carpeta. No es necesario abrir una carpeta para confirmar.
- Devuelve un mapa de destino explícito con id 0 e is_root true; cancelar sigue devolviendo null. Las fotos/videos usan folder_id 0, que ya consulta getMainPhotos; no requiere migrar la base de datos.
- Los llamadores de movimiento de carpetas traducen is_root a parent_id null, conservando el esquema de carpetas raíz. Se impide confirmar el destino actual y se mantienen las exclusiones de descendientes.
- Flujo: desde HUGO/misael, seleccionar una foto, Mover, Mover a Inicio. Si se navega dentro del selector, Regresar permite volver a Inicio.
- Análisis Dart del selector sin incidencias y diff sin errores de espacio. Pendiente comprobación funcional en teléfono.
## 26. ACT-014 — Desbloquear carpetas completas y papelera de carpetas (2026-09-20)

- Nuevo Desbloquear todo en el menú de cada carpeta y en selección múltiple, tanto en Inicio como en subcarpetas. Reúne fotos y videos de todos los niveles, sin duplicar archivos si se seleccionan destinos superpuestos; usa confirmUnlock y la transferencia verificada existente. Las carpetas quedan vacías; los archivos que fallen permanecen privados. No se añaden avisos de éxito.
- Eliminar una carpeta ahora la envía siempre a papelera con sus subcarpetas y archivos, conservando los originales cifrados. Esta acción sigue la petición explícita del usuario incluso si el ajuste Sin papelera está activo para archivos individuales.
- Esquema SQLite versión 4: columna nullable trash.folder_payload. Una entrada type=folder conserva un JSON de los registros de carpetas y fotos, incluidos metadatos de transferencia, fechas y portadas. El archivado y la retirada del árbol activo se realizan en una transacción; no se eliminan archivos del disco.
- La papelera distingue carpetas por icono y nombre, permite restaurarlas completas y borrarlas definitivamente. Restauración transaccional, padres antes que hijos, remapeo de IDs si hay colisión y retorno a Inicio si el padre original ya no existe. El borrado definitivo recorre los archivos del paquete; si falla conserva la entrada para reintentar.
- Se adapta también Vaciar papelera y la selección múltiple a paquetes de carpetas, incluidas carpetas vacías. Se conserva compatibilidad con entradas antiguas de fotos/videos.
- Archivos: db_helper.dart, media_service.dart, unlock_helper.dart, albums_screen.dart, folder_detail_screen.dart y trash_screen.dart.
- Pendiente verificación funcional en Android: carpeta con varios niveles, carpeta vacía, restauración con padre ausente y desbloqueo parcial. No se ha generado otro APK.
- Validación ACT-014: análisis Dart de los seis archivos sin errores; quedan advertencias previas de código sin uso y APIs obsoletas. No equivale a una prueba de restauración en dispositivo.

## 27. ACT-015 — Acerca de y explicación de privacidad (2026-09-20)

- Configuración incluye Información > Acerca de, con pantalla desplazable adaptada al tema y al área segura global.
- Explica almacenamiento local, cifrado de fotos/videos, verificación antes de eliminar originales, acceso, protección de capturas, camuflaje, papelera, compartir/desbloquear y respaldos.
- El texto describe la implementación actual sin prometer privacidad absoluta ni cifrado de todos los metadatos. Aclara que otras copias externas no se eliminan al ocultar, que compartir/desbloquear entrega contenido fuera de la bóveda y que la seguridad también depende del dispositivo.
- Archivos: about_screen.dart y settings_screen.dart. Análisis Dart sin errores; observaciones previas de APIs obsoletas en Configuración. Pendiente revisión visual en teléfono.
## 28. ACT-016 — Conservar carpetas al desbloquear (2026-09-20)

- Se comprobó que Desbloquear todo ya retira únicamente los archivos exportados y no elimina registros de carpetas.
- La confirmación de desbloqueo de carpetas ahora lo explica explícitamente: conserva carpeta y subcarpetas, y cualquier archivo cuyo desbloqueo falle permanece en su ubicación privada.
- Se elige la opción solicitada de conservar siempre la estructura. No se añade eliminación automática de carpetas al desbloquear; Enviar a papelera sigue siendo una acción independiente.
- Archivo: unlock_helper.dart. No cambia el motor de transferencia ni se añaden mensajes de éxito.
## 29. ACT-017 — Portadas de carpetas más visibles (2026-09-20)

- FolderThumbnail ahora usa la portada a todo el tamaño de la tarjeta, sin oscurecimiento general ni icono superpuesto cuando la imagen está disponible. Conserva un icono de carpeta como alternativa sin portada o si falla la imagen.
- Nombre y menú sobre una franja negra al 40 % de opacidad, dejando ver la imagen detrás. Se elimina la franja opaca que antes ocupaba espacio separado.
- Se sustituye el triángulo azul del contador por una etiqueta negra translúcida y redondeada con icono de imágenes y cantidad. La selección conserva borde y marca con el color del tema.
- Se oculta el número de subcarpetas tanto en la cuadrícula como en las filas de lista de Inicio y carpetas. No se modifica la jerarquía ni la navegación.
- Se conserva la carga diferida y la caché existente. Análisis Dart de FolderThumbnail sin incidencias; pendiente revisión visual en teléfono.
## 30. ACT-018 — Cierre al ocultar videos grandes (2026-09-21)

- Causa probable identificada por revisión: getVideoThumbnail descifraba el video completo mediante decryptBytes (varias copias entre Java/canal/Dart) y podían ejecutarse dos lecturas simultáneas. Al reabrir la galería se repetía el trabajo. No se obtuvo logcat del teléfono para confirmar OOM.
- Miniaturas de video ahora descifran por bloques a un temporal privado mediante prepareExportFile y ejecutan una sola extracción de video a la vez, con dimensiones acotadas. La cola de fotos mantiene su límite independiente.
- Reproducción y compartir usan temporales privados exclusivos con descifrado por bloques; no transportan videos completos por MethodChannel. Se limpian al terminar. Las filas de listas usan miniaturas y getPhotoThumbnail deriva los videos a su ruta correcta. getPhotoBytes rechaza videos para impedir lecturas completas accidentales.
- El método nativo de bytes en memoria rechaza archivos cifrados con carga superior a 32 MiB y convierte OutOfMemoryError del trabajador en error del canal. Archivos grandes se pueden transferir por bloques; una foto superior a ese límite puede carecer de previsualización. No es una garantía frente a toda falta de memoria o fallo de codec.
- No se borran registros ni archivos de la bóveda para esta reparación. Actualizar sin desinstalar/borrar datos. Pendiente confirmar modelo, tamaños y etapa del cierre con el usuario.
- Análisis de servicios y reproductor sin incidencias; nueve vectores de compatibilidad Java/Dart correctos. Se prepara una APK release de reparación; validación funcional con los videos del usuario pendiente.
## 31. ACT-019 — Auditoría y correcciones preventivas (2026-09-21)

- Informe con hallazgos, cambios, evidencia y pendientes en REVISION_FALLOS.md.
- Bloqueo elimina rutas privadas antes de esperar preferencias; inicio falla cerrado si no puede leer acceso; se impide regenerar claves sobre archivos existentes y se desactiva resetOnError en almacenamiento seguro. Se corrige cierre del onboarding y actualización del método de acceso.
- Papelera de fotos transaccional e idempotente ante dobles restauraciones. Esquema actual 5 (archivo secret_gallery_v3.db sin renombrar), añade photo_payload para conservar metadatos completos. Compatible con entradas anteriores.
- Respaldos: exportación a disco en worker, extracción previa en staging, rechazo de rutas/duplicados, validación SQLite/archivos referenciados, remapeo de rutas, copia de rollback y registro protegido sg_restore_rollback. AppEntry intenta recuperar una restauración interrumpida antes de cargar acceso. Interacción bloqueada mientras se procesa un respaldo. VaultActivity impide solapar respaldos con transferencias activas o en cola.
- Se liberan controladores tras fallar la inicialización de video. Se conserva el contenido privado existente.
- 27 pruebas sintéticas aprobadas (audit_regression_test, missing_key_test y pruebas anteriores de transferencia/cifrado). Análisis de archivos principales sin errores; quedan observaciones de estilo.
- SG-002/003/004/006/008 tienen correcciones implementadas, con aceptación Android aún pendiente. SG-007 sigue abierto: metadatos de respaldo legibles y falta de autenticación integral del formato.
- No considerar la app certificada ni libre de fallos. Revisar los escenarios pendientes del informe antes de publicar.
## 32. ACT-020 — Contador de archivos protegidos (2026-09-21)

- Configuración contaba solo Home porque getAllPhotos filtraba folder_id = 0. Ahora consulta todos los registros activos de photos, incluyendo cualquier nivel de carpetas. Papelera mantiene su contador independiente.
- getMainPhotos conserva el filtro de Home; no cambia la ubicación ni la visualización de archivos en la galería.
- El conteo de videos incluye FLV, igual que el servicio de medios. Se comprueba mounted antes de actualizar las estadísticas tras la carga asíncrona.
## 33. ACT-021 — Arrastrar selección a carpetas (2026-09-21)

- En Home y dentro de carpetas, en cuadrícula y lista: seleccionar archivos, mantener pulsado uno seleccionado y arrastrarlo sobre una carpeta visible. El grupo muestra miniatura animada y cantidad; el destino se resalta con «Soltar aquí». Respeta la preferencia de ocultar previsualizaciones.
- Desplazamiento automático en los bordes y conservación del elemento arrastrado cuando sale del área visible. Soltar fuera cancela sin modificar archivos. No abre carpetas automáticamente durante el arrastre; para otros destinos sigue disponible el menú Mover.
- movePhotos usa una transacción, valida destino y registros y elimina IDs duplicados. El gesto conserva la selección si falla y la limpia al completar; no descifra ni copia medios para moverlos.
- Componentes compartidos en lib/shared/widgets/media_drag_move.dart. Pruebas de interacción en test/media_drag_move_test.dart; pendiente valoración visual y táctil en teléfono. Requiere nueva compilación para incluirlo en una APK.
## 34. ACT-022 — Vista predeterminada 5×5 (2026-09-21)

- getGridType usa grid5 cuando no existe una preferencia guardada. Home, carpetas y papelera también empiezan con grid5 mientras cargan preferencias.
- Se mantienen las opciones de diseño y se respeta cualquier vista elegida y guardada anteriormente. No requiere migración de datos. Pendiente incluir en la próxima APK.
## 35. ACT-023 — Carpetas arrastrables y orden manual (2026-09-26)

- En orden normal, seleccionar una carpeta y mantenerla pulsada de nuevo permite arrastrar la selección dentro de otra carpeta. Funciona en Home y subcarpetas, lista y cuadrícula. El menú Mover se conserva para otros destinos, incluido Home.
- Diseño y vista > Ordenar por > Orden manual permite mantener pulsado y arrastrar directamente una foto, video o carpeta antes/después de otra tarjeta. Mezcla carpetas y medios; arriba/abajo del destino determina la inserción. En este modo soltar ordena, no cambia el contenedor; el menú Mover sigue disponible. Se muestra una indicación del modo. Reordenar está desactivado durante búsquedas para no guardar un orden parcial.
- Esquema SQLite 6: manual_order nullable en photos/folders e índices photos_folder/folders_parent. Guarda posiciones por carpeta en una transacción y batch; solo escribe posiciones distintas, sin leer ni copiar archivos multimedia. Elementos nuevos o movidos se añaden al final del orden manual; cambiar a fecha/nombre no borra el orden guardado.
- moveFolders valida la cadena de padres y rechaza ciclos, destino propio, descendientes, destinos inexistentes y selecciones desaparecidas; movimiento grupal transaccional. El selector tradicional usa el mismo método. Restauración de respaldos admite esquema 6; archivo de base mantiene el mismo nombre.
- Aclaración del usuario: aumentar imágenes SOLO en el popup de mover. Sus tarjetas pasan de una referencia de 64 a 110 dp, con 2–5 columnas adaptables. La vista principal predeterminada sigue en 5×5.
- Pruebas: 37 aprobadas, incluyendo orden mixto, grupos, cancelación, desplazamiento, arrastre de carpetas, rechazo de ciclos y 10.000 registros sintéticos. Análisis sin errores, con avisos anteriores de estilo/deprecación. Falta comprobar migración SQLite y tacto/rendimiento con la bóveda real en Android; no se manipularon archivos del usuario.
## 36. ACT-024 — Contadores solo dentro de carpetas (2026-09-26)

- Home oculta la cantidad de archivos en tarjetas de carpetas y filas de lista. Las subcarpetas al entrar conservan sus contadores.
- FolderThumbnail añade showCount (true por defecto); Home usa false. La miniatura flotante de una carpeta raíz también oculta su total de archivos.
- Solo cambio visual. Sin pruebas ni nueva compilación, por petición del usuario.
## 37. ACT-025 — Arrastre permanente y popup 4×4 (2026-09-26)

- Orden manual predeterminado, también al actualizar instalaciones anteriores mediante migración única de preferencia manual_sort_default_v1. Se retira la opción Manual del panel; fecha, nombre y tamaño siguen disponibles. Arrastrar desde cualquier orden guarda automáticamente un nuevo orden personalizado.
- Arrastrar siempre disponible sin búsqueda activa. Mantener pulsado también inicia selección para permitir grupos. En carpeta destino: centro (50% central de altura) mueve dentro; borde superior/inferior coloca antes/después. En foto destino se reordena antes/después. Conserva protección contra ciclos.
- Popup de mover con 4 columnas fijas, conservando desplazamiento vertical; vista principal 5×5 sin cambios.
- Nombre ascendente utiliza comparador compartido que prioriza letras antes de números, ignora mayúsculas y trata vocales acentuadas/ñ para nombres en español. Aplicado a fotos, carpetas y selector de destino.
- Solo cambios de código y documentación. Sin pruebas ni compilación por petición del usuario.
## 38. ACT-026 — Elegir portada navegando por carpetas (2026-09-26)

- CoverPickerSheet muestra carpetas y archivos del nivel actual en cuatro columnas. Inicia dentro de la carpeta que se quiere personalizar; permite entrar a subcarpetas, regresar y acceder a Home para elegir contenido de otra carpeta.
- La portada se guarda siempre en folderId original, independientemente del destino explorado. No mueve ni duplica fotos. Se mantiene Quitar portada.
- Reemplaza la carga recursiva de todos los medios (incluida una lista SQLite no modificable que se intentaba ampliar) por consultas del nivel visible y miniaturas compartidas diferidas. Estados de carga, vacío y error con reintento; evita actualizaciones después de cerrar y selecciones repetidas durante guardado.
- Solo edición de código/documentación: sin ejecutar pruebas ni generar APK, según preferencia del usuario.
## 39. ACT-027 — Arrastre sin mensajes y selección por barrido (2026-09-26)

- Se retira la franja de instrucciones de Home/subcarpetas y los textos «Colocar antes/después» y «Soltar aquí» de los destinos de arrastre. Mover no añade el elemento a la selección.
- Soltar sobre una foto coloca el grupo en la posición anterior del destino y desplaza los elementos intermedios, sin preguntar ni depender de la mitad superior/inferior. La vista refleja el nuevo orden inmediatamente mientras se guarda; al fallar vuelve a los datos cargados. Se conserva mover dentro de una carpeta al soltar en su centro.
- Selector de importación: mantener pulsado y deslizar selecciona un rango de fotos/videos. Si empieza sobre un elemento seleccionado, desmarca el rango. Retroceder el dedo restaura la selección inicial fuera del rango. Bordes desplazan automáticamente; desplazamiento normal sin mantener pulsado no selecciona.
- Selección por barrido calcula índices con la cuadrícula de 5 columnas y actualiza únicamente los bordes del rango cambiado. Temporizador y controlador se limpian al terminar, salir o importar. No oculta archivos hasta pulsar Ocultar.
- Solo cambios de código/documentación. No se ejecutaron pruebas ni se generó APK por petición del usuario.
## 40. ACT-028 — Recuperar selección sin confundirla con arrastre (2026-09-26)

- Mantener pulsado y soltar sin desplazar el dedo inicia selección de una foto/video o carpeta. Después se seleccionan más mediante toques normales.
- Mantener pulsado y arrastrar conserva el movimiento sin seleccionar automáticamente. SelectedMediaDrag distingue una pulsación quieta (desplazamiento acumulado menor de 10 dp y sin destino aceptado) del arrastre.
- Aplicado en Home y subcarpetas, cuadrícula y lista. Sin pruebas ni compilación por preferencia del usuario.