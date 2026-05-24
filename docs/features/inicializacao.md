# Feature Spec: Abrir ao Inicializar

## Status

Planejada. Este documento define produto, UX, arquitetura e TDD para a opcao de abrir o Mac Metrics View ao iniciar sessao no macOS. Nao implementar codigo de producao antes dos testes e contratos abaixo estarem revisados.

## Objetivo

Permitir que o usuario escolha se o Mac Metrics View deve abrir automaticamente ao iniciar sessao no macOS, mantendo o comportamento nativo, transparente e reversivel.

## Escopo

### Incluido

- Toggle no popover para ativar ou desativar abertura ao iniciar.
- Registro do app como item de login do usuario atual.
- Leitura do estado real do item de login ao abrir o app.
- Tratamento de erro quando o macOS negar, bloquear ou falhar ao registrar o item.
- Estado visual simples para sucesso, desativado ou indisponivel.
- Testes unitarios com um servico fake antes da implementacao.

### Fora do escopo inicial

- Abrir antes do login do usuario.
- Servico em segundo plano separado.
- Launch daemon, launch agent manual ou edicao direta de `.plist`.
- Instalador/pkg dedicado.
- Solicitar privilegios administrativos.
- Sincronizar a preferencia entre usuarios diferentes do Mac.
- Notificacoes sobre falha de inicializacao.

## Decisao de Produto

A feature deve ser uma preferencia explicita do usuario. O app nao deve se registrar automaticamente para abrir ao iniciar sem acao direta.

Default recomendado:

- `false`: nao abrir ao inicializar no primeiro lancamento.

Texto do controle:

```text
Abrir ao inicializar
```

## UX

### Local do Controle

O toggle deve ficar no popover, abaixo das configuracoes principais de metricas ou proximo da acao de sair, em uma area de preferencias simples.

Regras:

- Usar toggle nativo SwiftUI.
- Label: `Abrir ao inicializar`.
- O controle deve refletir o estado real do macOS quando o popover abrir.
- Ao ligar, registrar o app como item de login.
- Ao desligar, remover o app dos itens de login.
- Se a operacao falhar, reverter o toggle para o estado real conhecido.
- Nao exibir texto longo explicativo dentro do app.

### Estados

Estados esperados:

- `Desativado`: o app nao esta registrado para abrir ao iniciar.
- `Ativado`: o app esta registrado para abrir ao iniciar.
- `Indisponível`: o app nao consegue consultar ou alterar o item de login.
- `Erro`: a ultima tentativa de alterar o estado falhou.

O estado `Erro` deve ser discreto. A primeira versao pode mostrar apenas o toggle revertido e uma linha curta, por exemplo:

```text
Nao foi possivel alterar agora.
```

## Comportamento Esperado

- O usuario liga `Abrir ao inicializar`.
- O app registra o bundle atual como item de login.
- O app confirma o estado real depois da tentativa.
- Ao reiniciar ou entrar novamente no macOS, o app abre sem mostrar Dock icon, mantendo o comportamento de menu bar.
- O usuario desliga `Abrir ao inicializar`.
- O app remove o registro do item de login.
- O app nao abre automaticamente em proximos logins.

## Arquitetura

### Fonte Recomendada

Usar `SMAppService.mainApp` do framework `ServiceManagement`.

Racional:

- API moderna da Apple para login items de apps.
- Evita scripts, `launchctl`, edicao manual de plists e privilegios administrativos.
- Compatível com o objetivo de app nativo, local e discreto.
- O projeto tem target minimo macOS 14, entao a API moderna e adequada.

### Protocolo Recomendado

```swift
protocol LaunchAtLoginManaging {
    var status: LaunchAtLoginStatus { get }
    func setEnabled(_ isEnabled: Bool) throws
}
```

### Modelo Recomendado

```swift
enum LaunchAtLoginStatus {
    case enabled
    case disabled
    case unavailable
    case error
}
```

### Servico Recomendado

- `LaunchAtLoginManager`: encapsula `SMAppService.mainApp`.
- `LaunchAtLoginSettings`: estado observavel para UI.
- `LaunchAtLoginError`: erros de registro, remocao e consulta.

Regras:

- A UI nao deve chamar `SMAppService` diretamente.
- O servico deve ser pequeno e testavel por injecao de dependencia.
- O estado salvo em `UserDefaults`, se existir, deve ser apenas um cache da intencao do usuario, nunca a fonte de verdade.
- A fonte de verdade deve ser o status retornado pelo macOS.

## Persistencia

`SMAppService` registra o item de login no macOS. `UserDefaults` pode armazenar a ultima intencao do usuario para UX, mas nao deve substituir a consulta ao sistema.

Regras:

- Ao iniciar o app, consultar o status real.
- Ao abrir o popover, atualizar o status real.
- Ao alterar o toggle, tentar aplicar no macOS e entao consultar novamente.
- Se houver divergencia entre `UserDefaults` e macOS, o status do macOS vence.

## TDD

### Ordem Recomendada

1. Testar mapeamento de status do gerenciador para estado de UI.
2. Testar que o default do controle e `Desativado` quando o sistema retorna disabled.
3. Testar que ligar o toggle chama `setEnabled(true)`.
4. Testar que desligar o toggle chama `setEnabled(false)`.
5. Testar que falha ao ativar reverte o estado visual.
6. Testar que falha ao desativar reverte o estado visual.
7. Testar que o status real do sistema vence o cache local.
8. Testar que abrir o popover atualiza o estado antes de renderizar.
9. Testar que o app nao inicia samplers extras por causa da preferencia de login.
10. Testar que a feature nao altera visibilidade de CPU, RAM, Network ou Temperatura.

### Casos Unitarios Obrigatorios

- Status `.enabled` formata como `Ativado`.
- Status `.disabled` formata como `Desativado`.
- Status `.unavailable` formata como `Indisponível`.
- Status `.error` formata como `Erro`.
- View model inicia com status consultado do manager fake.
- Ao ligar o toggle, manager fake recebe chamada para ativar.
- Ao desligar o toggle, manager fake recebe chamada para desativar.
- Se ativacao falhar, toggle volta para desligado.
- Se desativacao falhar, toggle volta para ligado.
- `UserDefaults` nao sobrescreve o status real do manager.
- Mudanca de abrir ao inicializar nao dispara callbacks de lifecycle dos samplers.
- Mudanca de abrir ao inicializar nao altera `MetricVisibilitySettings`.
- Mudanca de abrir ao inicializar nao altera `MetricDisplaySettings`.

### Verificacao Manual

- Toggle `Abrir ao inicializar` aparece no popover.
- Toggle inicia desligado em uma instalacao limpa.
- Ligar o toggle registra o app nos itens de login do macOS.
- Desligar o toggle remove o app dos itens de login.
- Sair e abrir o app novamente preserva o estado real.
- Reiniciar sessao com toggle ligado abre o app na barra de menus.
- Reiniciar sessao com toggle desligado nao abre o app automaticamente.
- O app continua sem Dock icon durante abertura automatica.
- A preferencia nao altera CPU, RAM, Network ou Temperatura.

## Criterios de Aceite

- Usuario consegue ativar e desativar abertura ao iniciar pelo popover.
- O app usa API nativa do macOS para item de login.
- O app nao pede senha de administrador.
- O app nao usa `launchctl`, shell scripts ou edicao manual de plist em producao.
- O toggle reflete o estado real do macOS.
- Falhas sao tratadas sem deixar o UI mentindo sobre o estado.
- A abertura automatica preserva o comportamento de menu bar sem Dock icon.
- Testes cobrem status, sucesso, falha, cache e isolamento das metricas.

## Perguntas Abertas

- O controle deve ficar junto das metricas ou abaixo de um pequeno grupo `Preferencias`?
- Devemos mostrar uma mensagem discreta de erro ou apenas reverter o toggle?
- Builds locais unsigned terao alguma limitacao pratica diferente dos builds assinados/notarizados?
