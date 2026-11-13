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

### Hecho (sesión 1)
- Carpeta `Solpus/` creada (renombrada desde un nombre provisional).
- `README.md`, `.gitignore`, `docs/PLAN.md` (v2), `docs/WORKFLOW.md` y
  `docs/adr/0001-frontera-con-el-sdk.md`.
- Plan **aprobado** por la persona responsable.

### No hecho
- Sin repositorio Git, remoto, issues ni tarjeta de Trello.
- Sin código, `cabal.project` ni CI.
- Nada se compiló ni se probó contra un validador.

## 5. Siguiente paso

1. La persona responsable autoriza crear el repositorio remoto `Solpus` y los
   issues #1–#4 (acción remota).
2. `git init` local y rama `chore/1-esqueleto-monorepo`.
3. Spike #4 antes que el resto.

## 6. Archivos relevantes

- `docs/PLAN.md` — versiones, arquitectura, fases e issues.
- `docs/WORKFLOW.md` — flujo y reglas de Git.
- `docs/adr/0001-frontera-con-el-sdk.md` — decisión sobre el SDK.
