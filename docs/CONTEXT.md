# Solpus — Contexto y estado de la sesión

> Última actualización: 2026-11-12 · Sesión 1
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

- Base: `solana-haskell-sdk` **1.3.0.0** sobre **GHC 9.6.7**, aislado en
  `solpus-client` (ver ADR 0001).
- Monorepo cabal: `solpus-core`, `solpus-client`, `solpus-app`, `solpus-cli`.
- Red de pruebas por defecto; mainnet bloqueado hasta decisión escrita.
- Sin librería de logging en la primera versión.
- Flujo de trabajo adaptado de `PLAN-MODE-OCTOPUS` a Haskell (`WORKFLOW.md`).
- Reglas permanentes de la persona responsable: usar el filesystem para
  trabajar con archivos y **abrir siempre una PR al hacer push de commits nuevos**.

### Versiones

- Verificadas en Hackage: GHC 9.6.7 (probado por el SDK), `base` 4.18, `aeson`
  2.2, `text` 2.0, `bytestring` 0.11, `web3` y `web3-provider` 1.1.
- **1.4.0.0 del SDK existe pero no se pudo leer** (Hackage bloqueó la consulta).
  No se adopta; se evalúa en el spike #4.
- El resto (cabal, fourmolu, hlint, tasty, hedgehog, optparse-applicative,
  websockets, wuss) se resuelve y congela en los issues #1 y #2.

## 4. Estado actual

### Hecho
- Carpeta `Solpus/` creada (renombrada desde un nombre provisional).
- `README.md`, `.gitignore`, `docs/PLAN.md` (v2), `docs/WORKFLOW.md` y
  `docs/adr/0001-frontera-con-el-sdk.md`.
- Plan **aprobado** por la persona responsable (2026-11-12).
- Repositorio **privado** `MarianC-programing/Solpus` creado; `main` publicado
  con el commit inicial de documentación.
- Issues #1–#13 creados con la numeración del plan; #14 para las plantillas.
- Etiquetas de tipo, área, prioridad, riesgo y estado.
- Ajustes del repo: solo *squash merge*, rama borrada tras el merge.
- Protección de `main`: PR obligatorio, historial lineal, sin force push ni
  borrado, conversaciones resueltas, vigente también para administradores.
  Sin checks obligatorios todavía (no existe CI; se añaden en el issue #2).
- Plantillas de issue y PR, `.editorconfig`, `.gitattributes`, `CODEOWNERS`
  (issue #14).

### No hecho
- Sin tarjeta de Trello (opcional en este proyecto).
- Sin código, `cabal.project` ni CI.
- **La toolchain de Haskell no está instalada** en esta máquina (`ghc`, `cabal`
  y `ghcup` no existen). Nada se ha compilado ni probado; el issue #1 necesita
  instalarla (GHC 9.6.7).

### Notas de entorno
- `ProyectosDev/` es a su vez un repositorio Git (sin commits ni remoto).
  `Solpus/` tiene su propio `.git`; no ejecutar comandos de Git desde el padre.
- La clave SSH de esta máquina no está aceptada por GitHub, así que el remoto
  usa HTTPS con el helper de `gh` configurado solo en este repo
  (`credential.helper` local).

## 5. Siguiente paso

1. Revisar y mergear el PR de plantillas (issue #14), con autorización explícita.
2. Instalar GHC 9.6.7 y cabal con `ghcup` (requiere autorización: toca la máquina).
3. Issue #1 en la rama `chore/1-esqueleto-monorepo`; después #4 (spike).

## 6. Archivos relevantes

- `docs/PLAN.md` — versiones, arquitectura, fases e issues.
- `docs/WORKFLOW.md` — flujo y reglas de Git.
- `docs/adr/0001-frontera-con-el-sdk.md` — decisión sobre el SDK.
