# Solpus

Cliente Solana en Haskell: una **librería** modular y una **CLI** para consultar
saldos, enviar SOL y operar con tokens SPL, con la red de pruebas como entorno
por defecto.

> Estado: **fase 0 en curso**. Existe el esqueleto del monorepo; todavía no hay
> lógica de Solana. El plan está en
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
├── <paquete>/test/ suites de pruebas, dentro de cada paquete
└── docs/            contexto, plan, flujo de trabajo y ADRs
```

## Documentación

| Documento | Contenido |
| --- | --- |
| [`docs/PLAN.md`](docs/PLAN.md) | Versiones, arquitectura, fases e issues con criterios de aceptación |
| [`docs/CONTEXT.md`](docs/CONTEXT.md) | Estado actual, decisiones y siguiente paso |
| [`docs/WORKFLOW.md`](docs/WORKFLOW.md) | Flujo de trabajo adaptado a Haskell |
| [`docs/adr/`](docs/adr/) | Decisiones de arquitectura duraderas |

## Requisitos

GHC 9.6.7 y cabal (por ejemplo con [`ghcup`](https://www.haskell.org/ghcup/)).

## Comandos

```bash
cabal build all
cabal test all
cabal run solpus-cli

# Integración contra un validador local (no corre en CI)
SOLANA_INTEGRATION=1 SOLANA_TEST_VALIDATOR=<ruta>/solana-test-validator \
  cabal test solpus-client:test:integration --test-show-details=direct
```

Los subcomandos de la CLI llegan en fases posteriores (ver
[`docs/PLAN.md`](docs/PLAN.md)).
