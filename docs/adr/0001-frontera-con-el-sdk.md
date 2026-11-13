# ADR 0001 — Frontera con el SDK de Solana

- Estado: **aceptado** (2026-11-12, con la aprobación del plan)
- Fecha: 2026-11-12

## Contexto

Necesitamos construir, firmar y enviar transacciones de Solana desde Haskell.
`solana-haskell-sdk` (Hackage, 1.3.0.0 al momento de redactar, probado con
GHC 9.6.7) cubre claves, transacciones, JSON-RPC, suscripciones WebSocket,
System Program y SPL Token.
Es un paquete joven, de un solo mantenedor y con pocas descargas.

## Decisión

1. Usar `solana-haskell-sdk ==1.3.0.0` como implementación inicial.
2. Importarlo **únicamente** desde `Solpus.Client.Rpc` y `Solpus.Client.Tx`.
3. Exponer al resto del código una interfaz propia, `MonadSolana`, con tipos
   de `solpus-core`.
4. Capturar en `solpus-client` las `JsonRpcException` que lanza `runWeb3'` y
   traducirlas a errores tipados.
5. Validar la elección con el spike #4 antes de construir sobre ella.

## Consecuencias

- Cambiar de SDK, o reemplazarlo, afecta a dos módulos.
- Hay una capa de traducción de tipos que mantener.
- Las pruebas de `app` no necesitan red ni el SDK.

## Alternativa descartada por ahora

Cliente JSON-RPC propio sobre `http-client` y una librería de criptografía
(`crypton`). Da control total pero obliga a implementar la serialización de
transacciones; solo se activa como plan B si el spike #4 muestra que el SDK no
sirve (versión de GHC incompatible, errores de serialización o abandono).

## Criterio de revisión

Reevaluar si el SDK queda sin mantenimiento, rompe con una versión nueva de
GHC, o el spike encuentra diferencias de serialización frente a vectores de
referencia.
