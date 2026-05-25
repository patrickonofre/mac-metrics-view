# Plan: Bloqueio temporário de teclado e trackpad ("modo limpeza")

Status: in-progress

## Objective

Permitir que o usuário bloqueie temporariamente teclado e trackpad/mouse por uma
duração escolhida, para limpar o MacBook sem disparar cliques ou digitação
indesejados. Sucesso = um botão **Iniciar** com **seletor de tempo** no popover;
ao iniciar, todo input do teclado e do trackpad é suprimido até o timer expirar
(ou até um aborto de segurança), com um overlay em tela cheia mostrando o tempo
restante. A liberação **sempre** acontece, mesmo em crash/quit. É opt-in, local,
sem telemetria.

## Análise de viabilidade

**Abordagem técnica.** A única forma privilege-free e estável de suprimir input
de hardware no macOS é um `CGEventTap` em `.cgSessionEventTap` (ou
`.cghidEventTap`) que escuta eventos de teclado, mouse e trackpad e retorna `nil`
no callback para **consumir** o evento. Não envolve IOKit/`hidutil` nem
desabilitar dispositivos.

**Pré-requisitos duros (decidem se a feature é possível):**

- **Permissão de Acessibilidade** (`AXIsProcessTrusted`) — sem ela o event tap
  não captura nada. É uma capacidade nova para o app e muda a postura de
  privacidade → precisa de decisão registrada.
- **App não-sandbox.** Event taps não funcionam sob App Sandbox. O projeto já
  distribui fora da App Store (zip beta a partir do `.xcodeproj`), então é
  compatível — mas a feature **inviabiliza** uma futura distribuição via App
  Store. Precisa ser uma decisão consciente.

**Limites do macOS (não controláveis):** alguns eventos de hardware nunca são
suprimíveis (botão de power, força-desligar segurando, `Cmd+Ctrl+Power`). Isso é
*positivo*: são válvulas de escape de último recurso. O sistema também pode
desabilitar o tap se o callback demorar (`kCGEventTapDisabledByTimeout`) — o
serviço precisa detectar e reabilitar.

**Risco dominante: travar o usuário para fora.** Se bloquearmos todo o input,
precisa existir garantia de saída. O contrato é: (a) timer de expiração
automática como mecanismo primário; (b) overlay com contagem regressiva sempre
visível; (c) failsafe que libera no quit/crash; (d) um aborto de emergência
deliberado. Esse trade-off é o coração do design e é detalhado na spec.

**Encaixe no produto.** É um desvio da identidade atual ("visualizador de
métricas"). Justifica entrada em `docs/TECH_DECISIONS.md` antes do código:
capacidade nova (Acessibilidade), nova superfície de risco e impacto em
distribuição.

## Phases

1. **Decisão de produto + permissões (spike).** Registrar TD em
   `docs/TECH_DECISIONS.md` (capacidade Acessibilidade, não-sandbox, fora da App
   Store). Provar o `CGEventTap` num spike mínimo: detectar/solicitar permissão,
   suprimir teclado+trackpad, reabilitar após timeout do tap. — *Resultado:
   viabilidade confirmada e decisão aprovada antes de qualquer UI.*
2. **`InputLockService` (Services/, sem UI).** Wrapper isolado do `CGEventTap`
   atrás de um protocolo testável: `start(duration:)`, `stop()`, estado
   observável (`idle/locked`, `remainingSeconds`), reabilitação automática do
   tap, e callback de expiração. Lógica de tempo/estado testável sem tocar no
   hardware. — *Resultado: motor de bloqueio testável e isolado.*
3. **Overlay de bloqueio + modelo de sessão.** `NSWindow` borderless em nível
   alto, em todas as telas e Spaces, opaco, com contagem regressiva e instrução
   ("Bloqueado para limpeza — Xs"). Modelo `LockSession` (duração, restante,
   motivo do fim). Opcional: impedir sleep do display durante o bloqueio.
   — *Resultado: usuário sempre vê o estado e o tempo restante.*
4. **Controles no popover.** Seletor de duração (presets, ex. 15s/30s/60s/2min) +
   botão **Iniciar**, com *gating* de permissão (se faltar Acessibilidade,
   mostrar CTA que abre Ajustes do Sistema → Privacidade e Segurança). Persistir
   última duração em `UserDefaults` (padrão do projeto). — *Resultado: feature
   acionável a partir da UI existente.*
5. **Segurança e failsafe.** Aborto de emergência (sequência deliberada e
   difícil de acionar por acidente, ex. segurar `Esc` por 3s — não consumida pelo
   tap); auto-liberação no fim do timer; liberação garantida em
   `applicationWillTerminate` e via watchdog para crash (o tap morre junto do
   processo, mas validar que não há estado residual). — *Resultado: impossível
   ficar permanentemente travado.*
6. **Testes + docs.** Unit tests do `InputLockService` (estado, tempo,
   reabilitação, expiração) com fake do tap; testes do modelo de sessão e
   formatação do contador. Atualizar `architecture.md`, `domain-catalog.md` e o
   TD. UI/overlay validado lançando o app de verdade (`xcodebuild`/`swift run`).
   — *Resultado: lógica coberta por testes e comportamento de UI verificado.*

## Risks

- **Travar o usuário para fora** — mitigação: timer primário + overlay com
  contagem + aborto de emergência + failsafe de quit/crash (Fase 5).
- **Permissão de Acessibilidade ausente/recusada** — mitigação: detectar antes de
  iniciar, desabilitar o botão e oferecer CTA para Ajustes; nunca iniciar sem
  permissão.
- **Sandbox/entitlements** — mitigação: confirmar build não-sandbox no
  `.xcodeproj`; documentar que inviabiliza App Store (TD na Fase 1).
- **Tap desabilitado por timeout do sistema** (`kCGEventTapDisabledByTimeout`) —
  mitigação: callback enxuto + reabilitação automática (Fase 2).
- **Aborto de emergência conflita com o objetivo de "limpar sem disparar nada"** —
  mitigação: usar gesto/tecla raro e sustentado; documentar o trade-off na spec.
- **Mudança de postura de privacidade/identidade do produto** — mitigação:
  decisão explícita registrada em `TECH_DECISIONS.md` antes do código.

## Dependencies

- Permissão de **Acessibilidade** concedida pelo usuário (runtime).
- Build **não-sandbox** (configuração do `MacMetricsView.xcodeproj`).
- APIs do sistema: `CGEvent`/`CGEventTap` (CoreGraphics), `AXIsProcessTrusted`
  (ApplicationServices), `NSWindow` em nível elevado (AppKit).
- Toca: `Services/` (novo `InputLockService`), `App/` (`CPUState`/`AppDelegate`
  para wiring e failsafe de terminação), `UI/PopoverView.swift` (controles),
  `Models/` (settings de duração + `LockSession`), e `TECH_DECISIONS.md`.

## Out of scope

- Bloquear eventos de hardware impossíveis de suprimir (power, força-desligar).
- Distribuição via App Store / sandbox (esta feature é incompatível).
- Bloqueio agendado/recorrente ou por proximidade; apenas início manual.
- Senha/biometria para desbloquear antes do timer (o contrato é o timer + aborto).
- "Modo criança"/lock persistente entre reinícios — o bloqueio é sempre efêmero.

## Specs

- A escrever em `docs/ai/specs/` após aprovação (detalhar event tap, escape
  hatch, formato do overlay, presets de duração e matriz de testes).
