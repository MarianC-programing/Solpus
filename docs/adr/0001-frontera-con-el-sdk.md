# ADR 0001 — Frontera con el SDK de Solana

- Estado: **aceptado**, versión revisada tras el spike #4
- Fecha: 2026-11-12 (propuesto) · 2026-11-13 (revisado con la evidencia del spike)
- Evidencia: [`docs/spikes/0001-sdk.md`](../spikes/0001-sdk.md)

## Contexto

Necesitamos construir, firmar y enviar transacciones de Solana desde Haskell.
`solana-haskell-sdk` cubre claves, transacciones, JSON-RPC, suscripciones
WebSocket, System Program y SPL Token, y declara `tested-with: GHC 9.6.7`. Es un
paquete joven, de un solo mantenedor y con pocas descargas, y arrastra un árbol
grande de dependencias (127 paquetes en una compilación en frío, incluidos
`web3` y `web3-ethereum`).

## Decisión

1. Usar `solana-haskell-sdk ==1.4.0.0`. El plan inicial fijaba la 1.3.0.0; el
   spike mostró que ambas se comportan igual con el mismo código y que la 1.4.0.0
   corrige defectos que nos afectan (`transferChecked` independiente, `mkPrivateKeyFromBytes`
   y la decodificación base58 de datos de cuenta).
2. Importarlo **únicamente** desde `Solpus.Client.Rpc` y `Solpus.Client.Tx`.
3. Exponer al resto del código una interfaz propia, `MonadSolana`, con tipos de
   `solpus-core`. `solpus-core` no depende del SDK.
4. Usar la capa baja del SDK (`Core.Message`, `RPC.HTTP.Transaction`) con
   `preflightCommitment = confirmed`, y no el módulo `SolanaWeb3`, que el propio
   SDK documenta como apto solo para scripts y demos.
5. **Los errores del SDK son excepciones, no valores `Left`.** `solpus-client`
   envuelve cada llamada con `try` y traduce tres familias a `SolpusError`:
   `JsonRpcException` (RPC), `HttpException` (red) y `ErrorCall` (direcciones
   inválidas por `IsString`). Cualquier otra excepción se trata como defecto y
   no se oculta.
6. No construir direcciones con `IsString` del SDK (es parcial). Se parsean con
   `parseAddress` de `solpus-core`, contrastado en pruebas con
   `mkPublicKeyFromString` del SDK (issue #7).
7. La confirmación usa `awaitSignature` por WebSocket en `confirmed` por
   defecto (0,14–0,39 s en el spike, frente a 13–14 s de finalización).
8. Las lecturas llevan commitment propio: `getBalance` se invoca con una
   llamada propia (`remote "getBalance"` con `ConfigurationObject`), porque el
   del SDK no admite commitment y lee a `finalized` (issue #7).
9. La URL del nodo se trata como secreto: nunca aparece en errores ni logs, y
   el `Show` de `Endpoint` oculta ruta y consulta. Los errores de red usan un
   texto fijo sin la petición (issue #7).

## Consecuencias

- Cambiar de SDK, o reemplazarlo, afecta a dos módulos.
- Hay una capa de traducción de tipos y de errores que mantener.
- Las pruebas de `solpus-app` no necesitan red ni el SDK.
- La primera compilación en frío es lenta (unos 15 minutos, estimación
  aproximada); la caché de CI es necesaria.
- Dependemos de un mantenedor único: el aislamiento de la decisión 2 es lo que
  limita ese riesgo.

## Alternativa descartada por ahora (plan B)

Cliente JSON-RPC propio sobre `http-client` y una librería de criptografía
(`crypton`). Da control total pero obliga a implementar la serialización de
transacciones. El spike #4 no mostró ninguna de las condiciones que la
activarían, así que sigue descartada.

## Criterio de revisión

Reabrir esta decisión si ocurre alguna de estas condiciones:

- el SDK queda sin mantenimiento o rompe con una versión nueva de GHC;
- aparecen diferencias de serialización frente a vectores de referencia;
- una versión nueva del SDK cambia el modelo de errores o los tipos de claves;
- el coste de compilación del árbol de dependencias deja de ser asumible.
