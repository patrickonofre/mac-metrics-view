# Spec: Bloqueio temporário de teclado e trackpad ("modo limpeza")

Status: ready
Plan: ../plans/plan-input-lock-for-cleaning.md
Decision: ../../TECH_DECISIONS.md (TD-008)

## Summary

Entrega um modo opt-in em que o usuário escolhe uma duração, toca **Iniciar**, e o
app suprime todo input de teclado e trackpad/mouse por aquele tempo para permitir a
limpeza física do MacBook sem efeitos colaterais. Um overlay opaco em tela cheia
mostra a contagem regressiva. O input é liberado automaticamente no fim do timer,
por um aborto de emergência deliberado, ou ao encerrar o app. Requer permissão de
Acessibilidade e build não-sandbox (TD-008). Local, sem telemetria, sem registro de
input.

## Functional requirements

### Controles (popover)
- **FR-1** O popover exibe uma seção "Modo limpeza" com um seletor de duração
  (presets: **15s, 30s, 1min, 2min, 5min**) e um botão **Iniciar**.
- **FR-2** A última duração escolhida é persistida e pré-selecionada na próxima
  abertura (padrão: **30s**).
- **FR-3** Se a permissão de Acessibilidade não estiver concedida, o botão
  **Iniciar** fica desabilitado e a seção mostra um aviso com uma ação **"Abrir
  Ajustes"** que leva a System Settings → Privacidade e Segurança → Acessibilidade.
- **FR-4** Iniciar fecha o popover e ativa o bloqueio imediatamente.

### Estado de bloqueio
- **FR-5** Enquanto bloqueado, eventos de teclado (keyDown/keyUp/flagsChanged) e de
  ponteiro (movimento, clique esquerdo/direito/outros, scroll, gestos de trackpad)
  são suprimidos — não chegam a nenhum app nem ao sistema.
- **FR-6** Um overlay opaco cobre **todas as telas** e aparece sobre tudo
  (inclusive apps em tela cheia), exibindo: título ("Bloqueado para limpeza"), a
  contagem regressiva em `m:ss` (ou `Xs` abaixo de 60s), e a instrução do aborto de
  emergência.
- **FR-7** A contagem regressiva atualiza pelo menos a cada 1s.

### Saída do bloqueio
- **FR-8** **Expiração:** ao chegar a 0, o input é liberado, o overlay some, e o app
  volta ao estado normal.
- **FR-9** **Aborto de emergência:** segurar **Esc** por **3s contínuos** libera o
  bloqueio antes do tempo. Esse evento específico não é suprimido pelo tap. O overlay
  mostra essa instrução e dá feedback do progresso do hold.
- **FR-10** **Failsafe de término:** se o app for encerrado (quit/crash) durante o
  bloqueio, o input é liberado (o tap morre com o processo); não pode restar estado
  que mantenha o sistema travado após reabrir.
- **FR-11** Após qualquer saída, a duração persistida permanece para a próxima sessão.

## Technical requirements

### Camada Services (sem UI)
- **TR-1** `InputLockService` (protocolo) + implementação `CGEventTapInputLock`:
  - `start(duration: TimeInterval)`, `stop(reason: LockEndReason)`.
  - Estado observável `@MainActor`: `phase: .idle | .locked`, `remaining: TimeInterval`.
  - Callback/delegate `onEnd(reason:)` (`.expired`, `.aborted`, `.terminated`).
  - Instala `CGEventTap` em `.cgSessionEventTap`, máscara cobrindo teclado + mouse +
    scroll + gestos; callback retorna `nil` para consumir, **exceto** o caminho do
    aborto (Esc sustentado), que é deixado passar / tratado para encerrar.
  - **Reabilita** o tap ao receber `kCGEventTapDisabledByTimeout` /
    `...ByUserInput`. O callback é enxuto (sem alocação pesada) para evitar timeout.
- **TR-2** `AccessibilityAuthorization` (protocolo) encapsula
  `AXIsProcessTrusted()` / prompt e a abertura do painel de Ajustes — injetável para
  testes.
- **TR-3** Um relógio injetável (reutilizar `MainRunLoopTimer`/equivalente) controla
  `remaining` e a expiração, para testabilidade sem `CGEventTap` real.

### Camada Models
- **TR-4** `CleaningLockSettings` (duração persistida em `UserDefaults`, chave
  versionada; default 30s) — segue o padrão de `MetricDisplaySettings`.
- **TR-5** `LockEndReason` enum (`expired`, `aborted`, `terminated`).
- **TR-6** Formatação do contador é uma função pura (testável), com clamp defensivo
  (nunca negativo, nunca acima da duração).

### Camada App
- **TR-7** `CPUState` (estado compartilhado) ganha o estado do lock e expõe
  `startCleaningLock(duration:)`; `AppDelegate` possui o `InputLockService`, faz o
  wiring do overlay, e implementa o failsafe em `applicationWillTerminate`.

### Camada UI
- **TR-8** `LockOverlayWindow` (`NSWindow` borderless, `level` acima de tudo,
  `collectionBehavior` em todos os Spaces + sobre full-screen, opaco) hospeda uma
  view SwiftUI com o contador e a instrução de aborto.
- **TR-9** Controles do "Modo limpeza" adicionados ao `PopoverView` com o gating de
  permissão (FR-3).
- **TR-10** Opcional: impedir sleep do display durante o bloqueio
  (`NSProcessInfo.beginActivity`/assertion); registrar em VALIDATION se incluído.

### Build/capabilities
- **TR-11** Target permanece **não-sandbox** (TD-008). Documentar em README a
  exigência de permissão de Acessibilidade na primeira execução.

## Edge cases

- Permissão revogada **durante** o bloqueio → o tap deixa de suprimir; tratar como
  fim de sessão seguro (liberar overlay, voltar a `.idle`).
- Conexão/desconexão de teclado/trackpad externo durante o bloqueio → tap de sessão
  cobre dispositivos novos; validar.
- Mudança de configuração de monitores durante o bloqueio → overlay deve recriar
  janelas para cobrir todas as telas.
- Tap desabilitado pelo sistema (`...ByTimeout`) → reabilitar e continuar contagem.
- `start` chamado já estando `.locked` → no-op (idempotente).
- Duração 0 ou negativa (entrada corrompida no `UserDefaults`) → clamp ao default.
- Aborto (Esc) solto antes dos 3s → não desbloqueia; progresso reseta.
- App em background quando `start` é disparado por agendamento futuro → fora de
  escopo (só início manual nesta versão).

## Acceptance criteria

- [ ] `InputLockService` com fake do tap: `start(duration:)` move `phase` para
      `.locked`, decrementa `remaining` até 0 e chama `onEnd(.expired)`.
- [ ] Reabilitação: ao injetar `kCGEventTapDisabledByTimeout`, o serviço reinstala o
      tap e a sessão continua (testado via fake).
- [ ] Aborto: simular hold de Esc por 3s chama `onEnd(.aborted)`; hold < 3s não.
- [ ] `stop(.terminated)` libera e zera o estado; após isso `phase == .idle`.
- [ ] Formatação do contador: pura, clampada (ex.: 90→"1:30", 5→"5s", -1→"0s",
      acima da duração→duração).
- [ ] `CleaningLockSettings` persiste/recupera a duração; valor inválido cai no
      default.
- [ ] Gating de permissão: com `AccessibilityAuthorization` fake "negada",
      `startCleaningLock` não inicia e expõe estado que desabilita o botão.
- [ ] UI verificada com o app lançado (`xcodebuild`/`swift run`): Iniciar bloqueia,
      overlay cobre todas as telas, contador regressa, expiração e aborto liberam.

## Non-goals

- Bloquear eventos de hardware não-suprimíveis (power, força-desligar).
- Distribuição via App Store / sandbox (incompatível — TD-008).
- Início agendado/recorrente, por proximidade, ou ao fechar a tampa.
- Desbloqueio por senha/biometria antes do timer.
- Persistir o bloqueio entre reinícios (sempre efêmero).
- Registrar, armazenar ou transmitir qualquer input.

## Tasks

- [x] task-001 — Models, settings, formatter
- [x] task-002 — AccessibilityAuthorization
- [x] task-003 — InputLockService (CGEventTap)
- [x] task-004 — LockOverlayWindow
- [x] task-005 — Wiring popover + AppDelegate + failsafe
- [ ] task-006 — Validação end-to-end + docs
