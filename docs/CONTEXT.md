# Solpus — Contexto y estado de la sesión

> Última actualización: 2026-11-19 · Sesión 4
> Leer este archivo antes de continuar (regla 1 del `CLAUDE.md` general).

## 1. Qué es el proyecto

Librería Haskell modular y CLI para operar en Solana desde el lado cliente
(saldos, transferencias de SOL, tokens SPL, confirmaciones). Detalle completo en
[`PLAN.md`](PLAN.md).

## 2. Origen

La persona responsable pidió implementar Solana en un proyecto Haskell, sin
código previo, y delegó el alcance, el nombre inicial y las versiones. Eligió
el nombre **Solpus** y aprobó el plan el 2026-11-12. Se comprobó que no existía
ningún `.cabal` en `/home/marian01/ProyectosDev/`.

## 3. Decisiones

- Base: `solana-haskell-sdk` **1.4.0.0** sobre **GHC 9.6.7**, aislado en
  `solpus-client` (ver ADR 0001 y `docs/spikes/0001-sdk.md`).
- Monorepo cabal: `solpus-core`, `solpus-client`, `solpus-app`, `solpus-cli`.
- Red de pruebas por defecto; mainnet bloqueado hasta decisión escrita.
- Sin librería de logging en la primera versión.
- Flujo de trabajo adaptado de `PLAN-MODE-OCTOPUS` a Haskell (`WORKFLOW.md`).
- Reglas permanentes de la persona responsable: usar el filesystem para
  trabajar con archivos y **abrir siempre una PR al hacer push de commits nuevos**.

### Versiones

- Verificadas en Hackage: GHC 9.6.7 (probado por el SDK), `base` 4.18, `aeson`
  2.2, `text` 2.0, `bytestring` 0.11, `web3` y `web3-provider` 1.1.
- Toolchain instalada con `ghcup` (2026-11-13): **GHC 9.6.7** (`base` 4.18.3.0) y
  **cabal-install 3.18.2.0**, en `~/.ghcup/bin`. `ghcup` también instaló HLS
  por su cuenta (no solicitado). No se modificó `.bashrc` ni `.profile`: para
  usarla hay que hacer `export PATH="$HOME/.ghcup/bin:$PATH"`.
- `index-state` fijado en `2026-11-13T18:09:53Z`; las dependencias de boot
  quedan congeladas en `cabal.project.freeze` (`text` 2.0.2, `bytestring`
  0.11.5.4).
- **SDK `solana-haskell-sdk` 1.4.0.0** (adoptada tras el spike #4, en lugar de
  la 1.3.0.0 prevista): mismos límites de dependencias, mismo comportamiento y
  correcciones relevantes. Detalle en `docs/spikes/0001-sdk.md`.
- Dependencias de pruebas congeladas en `cabal.project.freeze`: `hedgehog` 1.7,
  `tasty` 1.5.5, `tasty-hedgehog` 1.4.0.2, `tasty-hunit` 0.10.2.
- **Agave 4.4.1** (`solana-test-validator`), release oficial verificado por
  SHA-256, instalado fuera del repo en `~/.local/share/solpus-spike/` sin tocar
  `PATH` ni perfiles. Su RPC escucha en `0.0.0.0` y no se puede restringir:
  usarlo solo mientras dure cada prueba.
- `fourmolu` **0.21.0.0** y `hlint` **3.10**: binarios oficiales instalados en
  `.tools/bin` (ignorado por Git) con `sh scripts/install-tools.sh`. La suma de
  `fourmolu` coincide con el digest de GitHub; la de `hlint` se fijó en la
  primera descarga porque GitHub no publica digest para ese asset.
- Acciones de CI fijadas por SHA: `actions/checkout` v7.0.1,
  `haskell-actions/setup` v2.12.1, `actions/cache` v6.1.0.
- El resto (tasty, hedgehog, optparse-applicative, websockets, wuss) se
  resuelve y congela en los issues siguientes.
- `libnuma-dev` no está instalado y no hizo falta para compilar ni enlazar.

## 4. Estado actual

### Hecho
- Carpeta `Solpus/` creada (renombrada desde un nombre provisional).
- `README.md`, `.gitignore`, `docs/PLAN.md` (v3), `docs/WORKFLOW.md` y
  `docs/adr/0001-frontera-con-el-sdk.md`.
- Plan **aprobado** por la persona responsable (2026-11-12).
- Repositorio **privado** `MarianC-programing/Solpus` creado; `main` publicado
  con el commit inicial de documentación.
- Issues #1–#13 creados con la numeración del plan; #14 para las plantillas.
- Etiquetas de tipo, área, prioridad, riesgo y estado.
- Ajustes del repo: solo *squash merge*, rama borrada tras el merge.
- Protección de `main`: PR obligatorio, historial lineal, sin force push ni
  borrado, conversaciones resueltas, vigente también para administradores, y
  checks obligatorios `build` y `lint` con rama actualizada (`strict`).
  Verificado con un PR desechable (#18, cerrado): `lint` falló, `build` pasó y
  el merge quedó bloqueado.
- Plantillas de issue y PR, `.editorconfig`, `.gitattributes`, `CODEOWNERS`
  (issue #14).
- Esqueleto del monorepo (issue #1): cuatro paquetes con módulos mínimos que
  prueban las aristas `cli → app → client → core`. `cabal build all
  --ghc-options=-Werror` compila sin advertencias y `cabal run solpus-cli`
  imprime `solpus-app -> solpus-client 0.1.0.0`. Sin el SDK todavía.
- Calidad y CI (issue #2): `fourmolu.yaml`, `.hlint.yaml`, workflow de CI con
  jobs `build` y `lint`, hooks nativos en `.githooks/` y scripts de
  instalación. Código existente formateado con fourmolu; `hlint` sin hallazgos.
- Spike #4 (`docs/spikes/0001-sdk.md`): el SDK funciona con GHC 9.6.7 y
  Agave 4.4.1. Errores como excepciones (no `Left`), confirmación por
  WebSocket en 0,14–0,39 s frente a 13–14 s de finalización, y 127 paquetes en
  frío. Se adopta la 1.4.0.0.
- Tipos y errores del dominio (issue #5), en `solpus-core` sin tocar el SDK:
  `Base58`, `Error` (validación, RPC y red), `Types` (`Address` de 32 bytes y
  `Signature` de 64, abstractos), `Lamports` (conversión exacta con `Nano`,
  aritmética comprobada, formato ASCII) y `Validate` (parsers totales con
  límites de longitud). Suite `unit` con 40 pruebas (`tasty` + `hedgehog`), que
  incluye un vector base58 independiente (`Hello World!`). `cabal test all`
  corre en `pre-push` y en CI.
- Interfaz de `solpus-client` e intérprete en memoria (issue #6):
  `Solpus.Client.Class` con **dos clases por mínimo privilegio**:
  `MonadSolanaRead` (`getBalance`) y `MonadSolana` (`submitTransfer`, que
  incluye la de lectura). Una función con restricción de solo lectura no puede
  gastar dinero; GHC rechaza el intento (comprobado compilando un caso
  negativo). La interfaz no lleva claves: quien firma lo resuelve la
  implementación real. `Solpus.Client.InMemory` imita lo observado en el spike
  (saldo 0 para cuentas desconocidas, `RpcError -32002` sin fondos). Suite
  `unit` con 10 pruebas, tres de ellas propiedades (el total de lamports se
  conserva, una transferencia fallida no toca el libro y una lectura nunca
  modifica el libro). Con las 9 pruebas originales, romper el crédito o el libro
  tras un fallo (pruebas de mutación) hizo fallar 6 y 3 de ellas.
- `scripts/check-boundaries.sh`: comprueba las fronteras de dependencia (SDK
  solo en `Rpc`/`Tx`, ninguna capa importa a otra superior, `solpus-app` solo
  importa la interfaz, y en sus pruebas el intérprete en memoria). Probado en
  positivo y con violaciones inyectadas; corre en CI y en `pre-push`.
- ADR 0001 (issue #3) revisado y aceptado con la evidencia del spike: SDK
  1.4.0.0, capa baja con `preflightCommitment = confirmed`, errores como
  excepciones traducidas a `SolpusError`, y confirmación por WebSocket.

- Configuración y lectura de saldo por RPC (issue #7, PR #23, mergeado), primer
  import del SDK 1.4.0.0, aislado en `Solpus.Client.Rpc`. `Config`: `Endpoint`
  abstracto (solo http/https; http solo a localhost; rechaza credenciales en la
  URL; su `Show` oculta ruta y consulta), `Commitment` por defecto `Confirmed`
  y timeout de respuesta de 1 a 300 s. `Rpc`: `getBalance` con llamada propia
  que admite commitment, porque el del SDK lee a `finalized` (demostrado en
  integración: 0 frente a 2 SOL justo tras confirmar un airdrop). Las
  excepciones del SDK se traducen a `SolpusError` sin incluir la URL. Decisión
  D11 y ADR 0001 (8–9). Pruebas: 40 de `solpus-core` y 32 de `solpus-client:unit`
  (incluye paridad con el SDK, 20.000 casos) y 3 de integración local con
  `solana-test-validator`, que no corren en CI.
  Limitaciones: sin prueba unitaria de `StatusCodeException`; la ruta
  `RpcError` en vivo no se provocó; devnet sin comprobar a mano; el timeout de
  conexión lo fija el SO.
- Gestión de wallet (issue #8, PR #24, mergeado). `Solpus.Client.Wallet` (tercer
  módulo que importa el SDK; `check-boundaries.sh` lo admite): `Wallet` abstracto,
  sin `Eq` y con `Show` que solo enseña la dirección (el del SDK imprime la
  clave). `loadWalletFile` abre sin seguir enlaces simbólicos y comprueba sobre
  el descriptor abierto: archivo regular, dueño, permisos 0600 o más estrictos
  (cualquier bit de grupo, otros o ejecución es error) y tamaño ≤ 1 KiB.
  `loadWalletEnv` acepta el mismo arreglo JSON de 64 bytes. Parser propio,
  total, sin dependencia nueva de JSON. Errores en `WalletError` (9
  constructores sin datos: ni clave, ni contenido, ni ruta). Pruebas: 15 nuevas
  (47 en `solpus-client:unit`), con clave centinela en todas las rutas de
  error y 2 propiedades del parser. Mutaciones detectadas: `Show` que expone la
  clave, permisos sin chequear y seguimiento de enlaces simbólicos. Sobrevive
  la omisión del chequeo de dueño: no se puede probar sin root (`chown`).
  Limitaciones: solo POSIX; sin protección frente a volcados de memoria ni a
  otros procesos del mismo usuario; el entorno es más débil que el archivo.
  La clave solo se usa dentro de `signInstructions` (issue #9).
- Transferir SOL (issue #9, en revisión). `Env` lleva una wallet opcional
  (`newEnvWith`); `submitTransfer` exige que el origen sea la wallet, consulta
  `getGenesisHash` y rechaza mainnet-beta (`MainnetRefused`) salvo
  `configAllowMainnet` (D5/D12); pide el blockhash a `confirmed`, firma con
  `Tx.buildTransfer` (puro: origen, importe cero, mensaje y firma verificables) y
  envía con preflight a `confirmed`. Nunca reintenta: un fallo de red o una
  respuesta ilegible tras enviar devuelve `SubmissionUncertain` con la firma y
  `lastValidBlockHeight` (el #10 añade resolverlo consultando el estado). Un
  error JSON-RPC del nodo (`RpcError`) significa que no entró. Caso de uso
  `Solpus.App.Transfer.transferSol` (rechaza importe cero). Pruebas: 62 en
  `solpus-client:unit` (15 nuevas, con un nodo HTTP falso local que comprueba
  orden de llamadas, commitment, guardia de mainnet y que solo hay un envío), 4
  en `solpus-app` y 7 de integración contra Agave 4.4.1 (la transferencia llega,
  la comisión que informa el nodo es 5000 y el origen paga monto más comisión).
  Mutaciones detectadas (8): sin guardia de mainnet, preflight y blockhash a
  `finalized`, sin chequeo de origen, firma mal extraída, reintento automático,
  constante de mainnet alterada e incierto tratado como `RpcError`.
  Hallazgos de la integración: fondos insuficientes llega como `RpcError -32002`
  («custom program error: 0x1»), una cuenta sin fondos como «no record of a prior
  credit» y un importe bajo la renta mínima a una cuenta nueva como «insufficient
  funds for rent»; no hay mapeo dedicado porque dependería del texto del nodo.
  Limitaciones: «confirmada» significa que el saldo llega a `confirmed` por
  sondeo (no hay WebSocket hasta el #10); un envío incierto no se resuelve solo;
  la comprobación de genesis añade una llamada por envío; revisión no
  independiente (la hará la persona responsable con otro agente).
- Integración en CI (issue #30, PR aparte): job informativo `integration` con el
  validador fijado por `scripts/install-validator.sh`.

### Desviaciones respecto al plan (issue #2)
- **Hooks nativos de Git en lugar de `lefthook`/`pre-commit`**: cero
  dependencias nuevas (ni Go ni Python). Se activan con
  `sh scripts/setup-hooks.sh`.
- **CI solo en `pull_request` y en `push` a `main`**, no en cada push a ramas
  de trabajo: un PR ya cubre esas ramas y se evita ejecutar todo dos veces.
- El hook `pre-commit` comprueba los archivos del árbol de trabajo, no el
  contenido exacto del índice; CI es el control definitivo.

### Desviaciones respecto al plan (issue #5)
- Las suites de pruebas viven dentro de cada paquete (`solpus-core/test/`) y
  no en un `test/` de la raíz: es la forma habitual de cabal.

### No hecho
- Sin tarjeta de Trello (opcional en este proyecto).
- Sin dependencia del SDK en los paquetes de producción (solo en el spike,
  fuera del repo); llega con los issues #6 y #7.

### Notas de entorno
- `ProyectosDev/` es a su vez un repositorio Git (sin commits ni remoto).
  `Solpus/` tiene su propio `.git`; no ejecutar comandos de Git desde el padre.
- La clave SSH (`~/.ssh/id_ed25519`) está registrada en GitHub y tiene
  passphrase. En la terminal de la persona responsable ya funciona (se creó
  `~/.ssh/config` con `AddKeysToAgent yes`; `ssh -T git@github.com` saluda).
  El shell del asistente no tiene `ssh-agent`, así que sigue sin poder usar SSH:
  el remoto usa HTTPS con el helper de `gh` configurado solo en este repo
  (`credential.helper` local).
- `hlint` y `fourmolu` viven en `.tools/bin`; `ghc`/`cabal` en `~/.ghcup/bin`.
  Ambos hay que añadirlos al `PATH` en cada shell.
- Los scripts de `scripts/` y `.githooks/` son ejecutables solo porque están
  marcados así en el índice de Git; el shell del asistente no permite `chmod`.

## 5. Siguiente paso

1. Cerrar el issue #9 (PR en revisión; revisión independiente a cargo de la
   persona responsable, CI y merge con autorización) y el #30 (CI).
2. Issue #10: confirmación por WebSocket y política de reintentos; incluye
   resolver un `SubmissionUncertain` consultando la firma.
3. Seguimiento (P3): #25 a #29 (mensaje de `RpcError`, excepciones relanzadas,
   redirecciones HTTP, ELOOP, `Show` de `Wallet`).

## 6. Archivos relevantes

- `docs/PLAN.md` — versiones, arquitectura, fases e issues.
- `docs/spikes/0001-sdk.md` — resultados del spike del SDK.
- `docs/WORKFLOW.md` — flujo y reglas de Git.
- [`docs/adr/0001-frontera-con-el-sdk.md`](adr/0001-frontera-con-el-sdk.md) —
  decisión sobre el SDK (aceptado, revisado tras el spike).
