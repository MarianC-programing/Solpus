# WORKFLOW — Solpus

Adaptación a Haskell de `PLAN-MODE-OCTOPUS`. Se conservan sus principios; se
simplifican los roles y se sustituyen las herramientas propias de JavaScript.

## Principio

**Planificar, ejecutar, comprobar, documentar y recién entonces pedir
autorización** para cualquier cambio externo o irreversible.

## Qué cambia respecto a PLAN-MODE-OCTOPUS

| PLAN-MODE-OCTOPUS | Aquí |
| --- | --- |
| pnpm, `package.json`, lockfile de npm | `cabal`, `cabal.project`, `cabal.project.freeze` versionado |
| Oxlint, `tsc -b` | `hlint`, compilación con `-Wall -Wcompat -Werror` |
| Husky + lint-staged | `pre-commit` o `lefthook` (fourmolu, hlint); `pre-push` con build y pruebas unitarias |
| Vitest, Playwright | `tasty`, `hedgehog`; integración con `solana-test-validator` |
| Roles separados siempre | Una persona o agente puede cubrir varios roles en tareas pequeñas; la revisión se hace en una pasada aparte y se declara en la PR |
| Tarjeta de Trello obligatoria | Opcional; se crea solo si la persona responsable lo pide |

## Flujo por issue

1. **Issue** con problema, resultado esperado, fuera de alcance, criterios de
   aceptación, prioridad, tipo y riesgo.
2. **Plan** breve en el issue (archivos, pasos, pruebas, riesgos). En riesgo
   medio o alto, requiere aprobación explícita antes de implementar.
3. **Rama** `tipo/numero-descripcion` (por ejemplo `feature/9-transferir-sol`).
   Nunca se trabaja en `main`.
4. **Implementación** mínima, con pruebas y documentación.
5. **Verificación local:**
   ```bash
   sh scripts/install-tools.sh        # una vez: fourmolu y hlint fijados
   sh scripts/setup-hooks.sh          # una vez por clon: activa .githooks/
   sh scripts/check-boundaries.sh
   cabal build all --ghc-options=-Werror
   cabal test all --ghc-options=-Werror
   .tools/bin/fourmolu --mode check $(git ls-files '*.hs')
   .tools/bin/hlint $(git ls-files '*.hs')
   ```
   Los hooks (`pre-commit`: formato y lint;
   `pre-push`: fronteras, build sin advertencias y `cabal test all`) y CI
   ejecutan lo mismo. `cabal test integration` se añade cuando el cambio
   toque red.
6. **Revisión** independiente del diff. Riesgo medio o alto: dos pasadas
   (corrección y seguridad; mantenibilidad y arquitectura). Los hallazgos
   `P0` y `P1` bloquean.
7. **Push y PR** con autorización.
8. **Merge** con CI en verde y autorización.
9. **Cierre:** actualizar `docs/CONTEXT.md` y cerrar el issue.

## Reglas de Git

1. Nunca se trabaja sobre `main`.
2. **Todo push de commits nuevos va acompañado de su pull request**: si la
   rama no tiene PR, se abre en el mismo paso; si ya la tiene, el push la
   actualiza y se comprueba que su descripción siga reflejando el diff.
3. No se hace `push` sin autorización explícita de la persona responsable.
4. No se hace merge sin autorización y con CI en verde.
5. No se usa `--no-verify`, `git push --force` ni `git reset --hard` sin
   autorización justificada.

## Contenido mínimo de una PR

- Issue relacionado y qué cambió.
- Relación con el plan aprobado.
- Pruebas ejecutadas, con resultados.
- Reporte de revisión.
- Cambios en `docs/CONTEXT.md` o ADRs.
- Declaración de independencia si una misma persona tuvo más de un rol.

## Seguridad

- Claves privadas, mnemónicos y tokens nunca entran al repositorio, a los
  logs, a las PR ni a la documentación.
- `.gitignore` excluye `*.json` de keypairs, `.env` y `test-ledger/`.
- Si una clave se expone por error, se considera comprometida: se rota y se
  informa.
- Las pruebas automáticas usan solo claves generadas al vuelo para el
  validador local.
- Mainnet exige decisión escrita de la persona responsable.

## Sin autorización se puede

Leer, analizar, planificar, editar en local, ejecutar pruebas locales contra
el validador local y preparar borradores.

## Requieren autorización

`push`, crear o editar PR, merge, cerrar issues, cambiar la protección de
ramas, administrar secretos y cualquier uso de mainnet.
