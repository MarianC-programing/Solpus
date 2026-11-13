# Solpus

Cliente Solana en Haskell: una **librería** modular y una **CLI** para consultar
saldos, enviar SOL y operar con tokens SPL, con la red de pruebas como entorno
por defecto.

> Estado: **plan aprobado, sin código todavía**. El plan está en
> [`docs/PLAN.md`](docs/PLAN.md) y la memoria operativa en
> [`docs/CONTEXT.md`](docs/CONTEXT.md).

## Qué es y qué no es

- Es el lado **cliente**: construir, firmar y enviar transacciones, leer cuentas,
  esperar confirmaciones.
- No incluye programas on-chain (en Solana se escriben normalmente en Rust).
- No toca mainnet hasta que la persona responsable lo decida por escrito.

## Base técnica

- GHC **9.6.7** y [`solana-haskell-sdk`](https://hackage.haskell.org/package/solana-haskell-sdk) **1.3.0.0**.
- El SDK se usa solo desde `solpus-client`, detrás de una interfaz propia.

## Estructura prevista

```text
Solpus/
├── cabal.project
├── solpus-core/     dominio puro, sin IO
├── solpus-client/   única frontera con solana-haskell-sdk
├── solpus-app/      casos de uso (transferir, saldo, tokens, confirmar)
├── solpus-cli/      ejecutable
├── test/            unitarias, propiedades e integración
└── docs/            contexto, plan, flujo de trabajo y ADRs
```

## Documentación

| Documento | Contenido |
| --- | --- |
| [`docs/PLAN.md`](docs/PLAN.md) | Versiones, arquitectura, fases e issues con criterios de aceptación |
| [`docs/CONTEXT.md`](docs/CONTEXT.md) | Estado actual, decisiones y siguiente paso |
| [`docs/WORKFLOW.md`](docs/WORKFLOW.md) | Flujo de trabajo adaptado a Haskell |
| [`docs/adr/`](docs/adr/) | Decisiones de arquitectura duraderas |

## Comandos (a partir de la fase 0)

```bash
cabal build all
cabal test unit
cabal run solpus-cli -- --help
```
