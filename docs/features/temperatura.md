# Feature Spec: Temperatura

## Status

Planejada. Este documento define produto, UX, arquitetura e TDD para a metrica de temperatura/estado termico. Nao implementar codigo de producao antes dos testes e contratos abaixo estarem revisados.

## Objetivo

Adicionar uma metrica opcional de temperatura ao Mac Metrics View para que o usuario entenda rapidamente se o Mac esta em condicao termica normal, aquecida, quente ou critica, mantendo o app leve, local e consistente com CPU, RAM e rede.

## Escopo

### Incluido

- Toggle de ativacao da metrica no popover, no mesmo padrao de CPU, RAM e Network.
- Persistencia da visibilidade em `UserDefaults`.
- Segmento opcional de temperatura na barra de menus quando a metrica estiver ativa.
- Detalhe de temperatura no popover quando a metrica estiver ativa.
- Historico curto em memoria para tendencia, quando houver valor numerico confiavel.
- Sampler independente, iniciado apenas quando a metrica estiver visivel.
- Fallback quando a temperatura numerica nao estiver disponivel.
- Estados de temperatura em portugues no UI.
- Testes unitarios antes da implementacao.

### Fora do escopo inicial

- Controle de ventoinhas.
- Alertas, notificacoes, sons ou automacoes.
- Diagnostico por sensor individual detalhado.
- Dependencia obrigatoria de `sudo`.
- Uso de `powermetrics` em producao.
- Prometer temperatura em graus Celsius em todos os Macs.
- App Store support garantido caso a leitura use APIs privadas.

## Decisao de Produto

A feature deve priorizar confiabilidade sobre falsa precisao.

O app deve sempre conseguir mostrar um estado termico oficial do macOS quando disponivel. Temperatura numerica em graus Celsius pode ser exibida somente quando o leitor conseguir obter um valor confiavel sem permissao elevada e sem custo relevante.

## Opcoes de Temperatura

Os estados exibidos ao usuario devem ser em portugues:

- `Normal`: condicao termica nominal.
- `Aquecido`: o sistema esta mais quente que o ideal, mas sem risco imediato.
- `Quente`: o sistema esta sob pressao termica relevante.
- `Crítico`: o sistema esta em condicao termica critica.
- `Indisponível`: nao foi possivel ler a condicao termica ou temperatura.

Mapeamento inicial recomendado:

| Fonte macOS | UI em portugues | Severidade |
| --- | --- | --- |
| `.nominal` | `Normal` | normal |
| `.fair` | `Aquecido` | warning |
| `.serious` | `Quente` | high |
| `.critical` | `Crítico` | critical |
| `.unknown` ou falha | `Indisponível` | unavailable |

## UX

### Toggle

O popover deve incluir um toggle curto:

```text
Temperatura
```

Regras:

- O toggle deve aparecer junto dos toggles de CPU, RAM e Network.
- Quando desligado, remove o segmento da barra de menus e a secao do popover.
- Quando desligado, para o sampler e impede novos pontos de historico.
- Quando ligado, reinicia o sampler e mostra fallback ate a primeira leitura valida.
- A escolha deve persistir entre lancamentos.

### Barra de Menus

Modo com icones:

```text
[thermometer] 68 °C
```

Modo com labels:

```text
TEMP 68 °C
```

Fallback com estado termico, quando graus Celsius nao estiverem disponiveis:

```text
[thermometer] Normal
TEMP Normal
```

Fallback sem leitura:

```text
[thermometer] --
TEMP --
```

Regras:

- Usar SF Symbol `thermometer` no modo de icones.
- Usar label `TEMP` no modo de labels.
- Nao mostrar valores numericos simulados.
- Nao mostrar `NaN`, infinito, valores negativos ou temperaturas fisicamente absurdas.
- Manter o segmento compacto para nao poluir a barra de menus.
- A cor deve seguir a severidade do estado termico:
  - `Normal`: cor padrao.
  - `Aquecido`: amarelo.
  - `Quente`: vermelho.
  - `Crítico`: vermelho, sem animacao.
  - `Indisponível`: cor secundaria ou padrao neutro.

### Popover

A secao de temperatura deve mostrar:

- Titulo: `Temperatura`.
- Valor principal: temperatura em Celsius quando disponivel, por exemplo `68 °C`.
- Estado: `Normal`, `Aquecido`, `Quente`, `Crítico` ou `Indisponível`.
- Tendencia curta somente quando houver amostras numericas validas.

Se so houver estado termico sem temperatura numerica, a secao deve esconder a tendencia numerica e mostrar o estado como valor principal.

## Modelo de Dados

### `TemperatureState`

Valores esperados:

- `.normal`
- `.warm`
- `.hot`
- `.critical`
- `.unavailable`

Formatacao em portugues:

- `.normal` -> `Normal`
- `.warm` -> `Aquecido`
- `.hot` -> `Quente`
- `.critical` -> `Crítico`
- `.unavailable` -> `Indisponível`

### `TemperatureSample`

Campos esperados:

- `timestamp: Date`
- `celsius: Double?`
- `state: TemperatureState`

Regras:

- `celsius` e opcional.
- Quando `celsius` for `nil`, o UI deve usar `state`.
- Quando `state` for `.unavailable`, o UI deve usar fallback `--` na barra de menus.
- Amostras invalidas nao devem chegar ao UI.

### `TemperatureHistory`

Regras:

- Guardar apenas amostras numericas validas.
- Manter historico curto em memoria, como 30 a 60 pontos.
- Remover as amostras mais antigas ao ultrapassar a capacidade.
- Nao persistir historico em disco.

### `MetricVisibilitySettings`

Campo planejado:

- `showTemperature: Bool`

Regras:

- Padrao recomendado: `false` no primeiro lancamento, por ser uma metrica com disponibilidade variavel entre Macs.
- Persistir em `UserDefaults`.
- Migrar usuarios existentes sem alterar as preferencias atuais de CPU, RAM e Network.
- `hasVisibleMetric` deve considerar temperatura.

## Arquitetura

### Fonte Primaria

Usar `ProcessInfo.processInfo.thermalState` como fonte primaria oficial para o estado termico.

Vantagens:

- API publica.
- Nao exige permissao elevada.
- Baixo custo.
- Funciona como fallback confiavel quando temperatura numerica nao estiver disponivel.

Limites:

- Nao fornece Celsius.
- Indica pressao termica agregada, nao sensor especifico.

### Fonte Opcional de Celsius

Um leitor separado pode tentar obter temperatura numerica via APIs nativas de baixo nivel, como SMC/IOKit, desde que:

- esteja isolado atras de um protocolo;
- falhe silenciosamente para `nil`;
- nao exija `sudo`;
- nao bloqueie a thread principal;
- tenha fallback imediato para o estado termico oficial;
- seja testavel com leitor fake.

### Protocolo Recomendado

```swift
protocol TemperatureReading {
    func readSample() -> TemperatureSample?
}
```

Implementacoes planejadas:

- `ProcessInfoTemperatureReader`: estado termico oficial, sem Celsius.
- `NativeTemperatureReader`: tentativa opcional de Celsius, com fallback.

### Sampler

Regras:

- Intervalo inicial sugerido: 5 segundos.
- Nao precisa atualizar a cada 1 segundo, pois temperatura muda mais lentamente que CPU/rede.
- Rodar somente quando `showTemperature` for true.
- Parar imediatamente quando o toggle for desligado.
- Publicar no `MainActor`.
- Nao coletar historico quando a metrica estiver escondida.

## TDD

### Ordem Recomendada

1. Testar formatacao dos estados em portugues.
2. Testar formatacao de temperatura em Celsius.
3. Testar fallback quando Celsius for `nil`.
4. Testar severidade de cada estado.
5. Testar historico numerico com limite de capacidade.
6. Testar configuracao `showTemperature` com default e persistencia.
7. Testar `hasVisibleMetric` considerando temperatura.
8. Testar titulo da barra de menus com temperatura visivel em modo icone.
9. Testar titulo da barra de menus com temperatura visivel em modo label.
10. Testar que esconder temperatura remove o segmento da barra de menus.
11. Testar que esconder temperatura impede novo historico.
12. Testar notificacao de lifecycle para iniciar/parar sampler.
13. Testar que alterar `identifierStyle` nao reinicia sampler de temperatura.
14. Testar acessibilidade com label explicito em portugues ou ingles consistente com o app.

### Casos Unitarios Obrigatorios

- `TemperatureState.normal` formata como `Normal`.
- `TemperatureState.warm` formata como `Aquecido`.
- `TemperatureState.hot` formata como `Quente`.
- `TemperatureState.critical` formata como `Crítico`.
- `TemperatureState.unavailable` formata como `Indisponível`.
- Temperatura `68.4` formata como `68 °C` ou `68.4 °C`, conforme decisao final de precisao.
- Celsius `nil` com estado `.normal` formata como `Normal`.
- Celsius `nil` com estado `.unavailable` formata como `--`.
- Valores `NaN`, infinito, negativos ou acima de limite plausivel sao rejeitados.
- Severidade `.normal` retorna estilo normal.
- Severidade `.warm` retorna estilo amarelo.
- Severidade `.hot` retorna estilo vermelho.
- Severidade `.critical` retorna estilo vermelho.
- Historico mantem a capacidade maxima e remove amostras antigas.
- Historico ignora amostras sem Celsius.
- Visibilidade de temperatura tem default `false`.
- Visibilidade de temperatura persiste em `UserDefaults`.
- Com labels, segmento mostra `TEMP`.
- Com icones, segmento nao mostra `TEMP`.
- Com todas as metricas ocultas, exceto temperatura, o status item mostra temperatura.
- Com todas as metricas ocultas, incluindo temperatura, o status item mostra `Metrics`.

### Verificacao Manual

- Toggle `Temperatura` aparece no popover junto das outras metricas.
- Ao ligar, surge segmento de temperatura na barra de menus.
- Ao desligar, segmento e secao de temperatura desaparecem.
- A preferencia persiste apos sair e abrir o app.
- O app nao pede senha.
- O app nao executa `powermetrics`.
- O app continua responsivo com a metrica ligada.
- Em Mac sem Celsius disponivel, o estado termico continua funcionando.
- UI fica legivel em modo claro e escuro.

## Criterios de Aceite

- Usuario consegue ativar e desativar temperatura pelo popover.
- A metrica desligada nao coleta novas amostras.
- O status item mostra Celsius quando disponivel.
- O status item mostra estado termico em portugues quando Celsius nao estiver disponivel.
- O popover mostra detalhe coerente com a disponibilidade da leitura.
- O app nao usa permissao elevada.
- O app nao faz chamadas externas.
- Testes unitarios cobrem formatacao, severidade, persistencia, historico e lifecycle.
- A implementacao preserva o comportamento existente de CPU, RAM e Network.

## Perguntas Abertas

- Exibir Celsius com zero ou uma casa decimal?
- O default deve ser desligado, como recomendado, ou ligado para descoberta da feature?
- A acessibilidade deve usar `Temperatura` em portugues ou manter idioma misto com `CPU`, `RAM`, `Network`?
- Se Celsius estiver disponivel, o estado termico deve aparecer como detalhe secundario ou badge de severidade?
