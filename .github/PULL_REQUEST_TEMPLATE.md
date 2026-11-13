## Issue relacionado
Closes #

## Qué cambió y por qué


## Relación con el plan aprobado
<!-- Enlace al comentario o sección del plan. Indicar cualquier desviación. -->

## Pruebas
<!-- Comandos ejecutados y resultado. No afirmar lo que no se ejecutó. -->
- [ ] `cabal build all`
- [ ] `cabal test unit`
- [ ] `hlint` y `fourmolu --mode check`
- [ ] `cabal test integration` (si el cambio toca red)
- [ ] Prueba manual (describir pasos y resultado)

## Revisión
<!-- Resultado: APROBADO | APROBADO CON SEGUIMIENTO | CAMBIOS SOLICITADOS.
     Riesgo medio o alto: dos pasadas (corrección y seguridad; mantenibilidad y arquitectura). -->

## Documentación y contexto
- [ ] `docs/CONTEXT.md` actualizado
- [ ] `README.md` actualizado (si cambia el uso)
- [ ] ADR nuevo o actualizado (si cambia una decisión duradera)

## Seguridad
- [ ] Sin claves, mnemónicos ni tokens en código, logs, tests ni documentación
- [ ] Sin uso de mainnet

## Riesgos, reversión y seguimiento


## Independencia
<!-- Declarar si una misma persona o agente cubrió más de un rol (planificación, implementación, revisión). -->
