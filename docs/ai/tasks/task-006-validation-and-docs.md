# Task: Validate end-to-end and update docs

Status: ready
Spec: ../specs/spec-input-lock-for-cleaning.md

## Goal

Provar todos os critérios de aceitação da spec e deixar a documentação coerente.

## Touches

- docs/ai/validation/validation-input-lock-for-cleaning.md (novo)
- docs/ai/architecture.md (seção do serviço de lock)
- docs/ai/domain-catalog.md (termos: modo limpeza, sessão de bloqueio, aborto)
- README.md (nota sobre permissão de Acessibilidade na 1ª execução)

## Steps

1. Rodar `swift test`; anexar evidência no registro de validação.
2. Lançar o app de verdade e percorrer a matriz de aceitação de UI da spec
   (bloqueio, overlay em todas as telas, expiração, aborto Esc-3s, failsafe de quit,
   gating de permissão).
3. Atualizar architecture/domain-catalog/README; marcar plan/spec como `done`.
4. Registrar riscos residuais (eventos não-suprimíveis; revogação de permissão em
   tempo de execução; mudança de monitores).

## Verification

- [ ] Todos os checkboxes de "Acceptance criteria" da spec marcados com evidência.
- [ ] `swift test` verde; comportamento de UI observado e registrado.
- [ ] Docs atualizadas; plan e spec em `done`.
