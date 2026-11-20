# PLAN — Solpus

> Versión 3 · 2026-11-13 · Estado: **plan aprobado** por la persona responsable
> (aprobación en la conversación del 2026-11-12). Las versiones y el nombre los
> decidió Claude por delegación. La v3 incorpora el resultado del spike #4
> (`docs/spikes/0001-sdk.md`): SDK 1.4.0.0.

## 1. Objetivo

Librería Haskell modular y CLI para operar en Solana desde el lado cliente:

- consultar saldos y cuentas;
- construir, firmar y enviar transacciones (SOL y tokens SPL);
- esperar confirmaciones sin sondeo cuando sea posible.

**Fuera de alcance:** programas on-chain, mainnet, custodia de claves de
terceros, interfaz web, indexador.

## 2. Versiones fijadas

| Componente | Decisión | Estado |
| --- | --- | --- |
| GHC | **9.6.7** | Verificado: es la versión con la que se probó el SDK |
| `base` | `>=4.18 && <4.19` | Verificado: es el límite que impone el SDK |
| `solana-haskell-sdk` | **1.4.0.0** (`==1.4.0.0`) | Verificado en el spike #4: compila y funciona con GHC 9.6.7; mismos límites que la 1.3.0.0 |
| `web3`, `web3-provider` | `>=1.1 && <1.2` | Verificado: límites del SDK |
| `aeson` | `>=2.2 && <2.3` | Verificado: límite del SDK |
| `text` | `>=2.0 && <2.1` | Verificado: límite del SDK |
| `bytestring` | `>=0.11 && <0.12` | Verificado: límite del SDK |
| `websockets` y `wuss` | las que resuelva cabal | El SDK no trae WebSocket: lo aportamos nosotros, solo en `solpus-client` |
| `tasty`, `tasty-hunit`, `hedgehog`, `optparse-applicative` | las que resuelva cabal con GHC 9.6.7 | Se congelan en `cabal.project.freeze` |
| `fourmolu`, `hlint` | **0.21.0.0** y **3.10** (binarios oficiales) | Verificado: `fourmolu` coincide con el digest de GitHub; `hlint` no publica digest y su suma se fijó en la primera descarga |
| `cabal-install` | **3.18.2.0** | Instalada con `ghcup` el 2026-11-13 |

Notas:

- **Se adopta la 1.4.0.0 del SDK** (decisión del spike #4, sustituye a la
  1.3.0.0 prevista inicialmente): mismos límites, mismo comportamiento y
  correcciones que afectan a los issues #8 y #11. Ver `docs/spikes/0001-sdk.md`.
- Los números que dependen de GHC 9.6.7 (herramientas y librerías de pruebas)
  no se inventan aquí: se resuelven en el issue #1 y quedan congelados con
  `cabal.project.freeze` y un `index-state` fijo en `cabal.project`.
- El SDK es de un solo mantenedor y tenía 34 descargas al verificarlo: de ahí
  el aislamiento de la sección 4.

## 3. Decisiones de diseño

| # | Decisión | Motivo |
| --- | --- | --- |
| D1 | Usar `solana-haskell-sdk` como base | Cubre claves, transacciones, RPC, WebSocket, System Program y SPL Token; declara pruebas contra vectores de los crates de Rust |
| D2 | Aislarlo en un solo paquete (`solpus-client`) | Si el SDK cambia o falla, solo se reescribe una capa |
| D3 | Dominio puro en `solpus-core` | Se prueba sin red ni mocks |
| D4 | Casos de uso sobre dos clases por mínimo privilegio (`MonadSolanaRead` y `MonadSolana`) | Las pruebas usan un intérprete en memoria; una función de solo lectura no puede gastar dinero y lo hace cumplir el compilador |
| D5 | Red por defecto: `solana-test-validator`, luego devnet | Sin riesgo económico; mainnet requiere decisión escrita |
| D6 | Monorepo cabal con varios paquetes | El compilador impone las fronteras |
| D7 | Errores como `Either SolpusError` en la API pública | El SDK lanza excepciones, no `Left` (spike #4): `JsonRpcException` (RPC), `HttpException` (red) y `ErrorCall` (direcciones inválidas por `IsString`). `solpus-client` las captura con `try` y las traduce; cualquier otra excepción se trata como defecto |
| D8 | Claves privadas solo desde archivo con permisos restringidos o variable de entorno; nunca en logs | Seguridad |
| D9 | Sin librería de logging en la primera versión; la CLI controla la salida | Menos dependencias y menos superficie de fuga de secretos |
| D10 | La confirmación pasa por `awaitSignature` con transporte WebSocket que aportamos nosotros | El SDK es agnóstico del transporte; `wss://` se resuelve cambiando a `wuss` |
| D11 | Las lecturas usan commitment propio (`getBalance` con llamada propia) y las URLs de nodo se tratan como secreto | El `getBalance` del SDK no admite commitment y lee a `finalized` (saldo 0 tras un airdrop confirmado); las URLs suelen llevar claves de API |
| D12 | Transferir usa `confirmed` para el blockhash y el preflight, rechaza mainnet por genesis hash salvo permiso expreso y nunca reintenta; un envío dudoso devuelve la firma y la última altura válida | Con los valores por defecto del SDK (`finalized`) el nodo vería saldo cero tras un airdrop; un reintento ciego podría duplicar el pago; la clave de un nodo real no debe gastar fondos reales por accidente |

## 4. Arquitectura

```text
Solpus/
├── cabal.project
├── solpus-core/
│   └── src/Solpus/Core/
│       ├── Types.hs        Address, Signature, Slot, Commitment
│       ├── Lamports.hs     Lamports y conversión a/desde SOL sin Double
│       ├── Error.hs        SolpusError (red, RPC, transacción, validación)
│       └── Validate.hs     validación de direcciones y montos
├── solpus-client/
│   └── src/Solpus/Client/
│       ├── Config.hs       endpoint, commitment, timeouts
│       ├── Class.hs        class MonadSolana (la interfaz)
│       ├── Rpc.hs          instancia real sobre el SDK (importa el SDK)
│       ├── Wallet.hs       carga y manejo de keypairs
│       ├── Tx.hs           construcción, firma y envío (importa el SDK)
│       └── Subscribe.hs    transporte WebSocket y confirmación
├── solpus-app/
│   └── src/Solpus/App/
│       ├── Balance.hs
│       ├── Transfer.hs     SOL
│       ├── Token.hs        SPL: cuenta asociada y transferChecked
│       └── Confirm.hs      política de confirmación y reintentos
├── solpus-cli/
│   └── app/Main.hs         optparse-applicative; solo parseo y salida
└── <paquete>/test/         suites de pruebas dentro de cada paquete (cabal)
    ├── unit                tasty + hedgehog (solpus-core ya la tiene)
    ├── golden              vectores de serialización (solpus-client)
    └── integration         contra solana-test-validator (solpus-client)
```

### Reglas de dependencia

```text
solpus-cli → solpus-app → solpus-client → solpus-core
                                  ↓
                        solana-haskell-sdk   (solo aquí)
```

- `solpus-core` no importa nada fuera de `base`, `text` y `bytestring`.
- Solo `Solpus.Client.Rpc` y `Solpus.Client.Tx` importan el SDK.
- `solpus-app` solo conoce la clase `MonadSolana`, nunca la implementación; en
  sus pruebas puede usar además el intérprete en memoria.
- La CLI no contiene lógica de negocio.
- `scripts/check-boundaries.sh` comprueba estas reglas (por texto, sobre las
  líneas `import`) en `pre-push` y en el job `lint` de CI. Los módulos de
  `solpus-client` que `solpus-app` pueda usar se listan allí de forma explícita.

## 5. Herramientas

| Área | Elección |
| --- | --- |
| Compilador y build | GHC 9.6.7 y cabal vía `ghcup` |
| Formato | `fourmolu` 0.21.0.0 (binario oficial, suma SHA-256 fijada en `scripts/install-tools.sh`) |
| Lint | `hlint` 3.10 (idem); compilación con `-Wall -Wcompat` y `-Werror` en CI y `pre-push` |
| Pruebas | `tasty`, `tasty-hunit`, `hedgehog` |
| CLI | `optparse-applicative` |
| CI | GitHub Actions: jobs `build` y `lint` (nombres estables, checks obligatorios de `main`); acciones fijadas por SHA; GHC 9.6.7 y cabal 3.18.2.0; se ejecuta en cada PR y en cada push a `main` |
| Hooks locales | Hooks nativos de Git versionados en `.githooks/` (sin dependencias extra), activados con `scripts/setup-hooks.sh`: `pre-commit` (fourmolu y hlint sobre los `.hs` preparados) y `pre-push` (`cabal build all --ghc-options=-Werror`) |

## 6. Fases e issues

Cada issue sigue `docs/WORKFLOW.md`. Prioridad `P0`–`P3` y riesgo entre paréntesis.

### Fase 0 — Fundación

- **#1 `chore: esqueleto del monorepo` (P1, bajo)**
  Paquetes vacíos que compilan, `cabal.project` con `index-state`, GHC 9.6.7
  fijado, `cabal.project.freeze`.
  *Aceptación:* `cabal build all` pasa en limpio; el grafo coincide con §4;
  versiones de cabal y librerías anotadas en `docs/CONTEXT.md`.
- **#2 `chore: calidad y CI` (P1, medio)**
  fourmolu, hlint, hooks, workflow de CI en PR, protección de `main`.
  *Aceptación:* un PR con código sin formato falla en CI; los hooks no se omiten.
- **#3 `docs: aceptar ADR 0001` (P2, bajo)**
  *Aceptación:* estado del ADR en "aceptado" y enlazado desde `CONTEXT.md`.
- **#4 `chore: spike del SDK` (P1, medio)**
  Probar el SDK contra `solana-test-validator`: generar clave, airdrop, balance,
  transferencia y `awaitSignature`. Evaluar de paso 1.4.0.0.
  *Aceptación:* script descartable que funciona y un informe en `CONTEXT.md`
  con versiones, advertencias y límites. Si falla, se replantea D1 antes de seguir.

### Fase 1 — Núcleo

- **#5 `feature: tipos y errores del dominio` (P1, bajo)**
  *Aceptación:* conversión SOL↔lamports sin `Double`; propiedad
  `fromSol . toSol == id`; direcciones inválidas rechazadas con error tipado.

### Fase 2 — Cliente

- **#6 `feature: interfaz MonadSolana e intérprete en memoria` (P1, medio)**
  *Aceptación:* `solpus-app` se prueba sin red.
- **#7 `feature: configuración y balance por RPC` (P1, medio)**
  *Aceptación:* `getBalance` contra el validador local y devnet; las
  `JsonRpcException` se traducen a `SolpusError`.
- **#8 `feature: gestión de wallet` (P0, alto)**
  *Aceptación:* ninguna ruta de log o error contiene la clave; permisos
  inseguros producen error. Revisión en dos pasadas.

### Fase 3 — Transacciones SOL

- **#9 `feature: transferir SOL` (P1, alto)**
  *Aceptación:* transferencia confirmada en el validador local; fondos
  insuficientes devuelven error tipado; prueba de integración.
- **#10 `feature: confirmación por WebSocket con reintentos` (P2, medio)**
  *Aceptación:* espera la firma sin sondeo; timeout configurable; la política
  de reintentos no reenvía transacciones duplicadas.

### Fase 4 — Tokens SPL

- **#11 `feature: cuenta asociada y transferChecked` (P2, alto)**
  *Aceptación:* crear mint de prueba, ATA y transferencia en el validador local.

### Fase 5 — CLI y cierre

- **#12 `feature: CLI` (P2, bajo)**
  Subcomandos `balance`, `transfer`, `token transfer`, con `--network` y
  `--dry-run`. *Aceptación:* `--help` documentado; mainnet rechazado salvo
  bandera explícita.
- **#13 `docs: README, guía de uso y CONTEXT` (P3, bajo)**

## 7. Estrategia de pruebas

- **Unitarias y de propiedades:** `solpus-core` y `solpus-app` con el
  intérprete en memoria. Corren en el hook `pre-push`.
- **Golden:** serialización de transacciones frente a vectores conocidos.
- **Integración:** contra `solana-test-validator`, con target aparte
  (`cabal test integration`). La suite del propio SDK se omite sola si no hay
  validador; la nuestra debe hacer lo mismo y fallar con `SOLANA_INTEGRATION=1`.
- **Manual:** la CLI en devnet antes de cerrar la fase 5.

## 8. Riesgos

| Riesgo | Mitigación |
| --- | --- |
| SDK joven y de un solo mantenedor | Spike #4, aislamiento en `solpus-client`, plan B en el ADR |
| Incompatibilidad de versiones | GHC 9.6.7 y límites del SDK fijados; `index-state` y freeze |
| Pérdida de fondos por error propio | Solo red de pruebas; `--dry-run`; mainnet bloqueado por defecto |
| Filtración de claves | #8 con pruebas dedicadas, `.gitignore` estricto, sin logging en v1 |
| Reenvío duplicado de transacciones | Política explícita en #10 |
| Excepciones del SDK que escapan | D7: capturarlas en `solpus-client`, con prueba que lo verifique |

## 9. Siguiente paso

1. La persona responsable autoriza crear el repositorio remoto y los issues
   #1–#4 (acción remota: requiere autorización explícita).
2. Se ejecuta #1 en una rama `chore/1-esqueleto-monorepo`.
3. El spike #4 se ejecuta antes que el resto; sus resultados pueden cambiar el plan.
