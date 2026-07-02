// Lightweight i18n for the static site. Mirrors the app's PT/EN support.
// Text nodes carry data-i18n="key"; image alts carry data-i18n-alt="key".
// PT is the default language. The pt and en key sets MUST stay identical — the
// release gate scripts/check-i18n-parity.mjs enforces that.
(function () {
  "use strict";

  var STRINGS = {
    pt: {
      "nav.whatsnew": "Novidades",
      "nav.demo": "Demo",
      "nav.features": "Recursos",
      "nav.privacy": "Privacidade",
      "nav.download": "Download",

      "hero.eyebrow": "Versão 2.5 para macOS",
      "hero.title": "Seu Mac inteiro, na barra de menus.",
      "hero.lede": "CPU, GPU, memória, rede, temperatura, disco, bateria e tokens de IA — tudo num relance, sem abrir o Monitor de Atividade.",
      "hero.cta": "Baixar 2.5",
      "hero.secondary": "Ver o que há de novo",
      "hero.note": "Sem conta. Sem telemetria. Leitura local dos indicadores do sistema.",
      "hero.altMenu": "Mac Metrics View na barra de menus do macOS mostrando CPU, RAM, rede, temperatura, disco e bateria",

      "sticky.label": "Mac Metrics View 2.5",
      "sticky.cta": "Baixar",

      "metric.cpu": "uso e processos",
      "metric.gpu": "uso do chip gráfico",
      "metric.ram": "apps, pressão e swap",
      "metric.net": "download e upload",
      "metric.temp": "estado térmico",
      "metric.disk": "leitura e escrita",
      "metric.bat": "carga e energia",
      "metric.ai": "tokens e custo",

      "highlights.eyebrow": "Destaques da série 2",
      "highlights.title": "Cada versão, um salto.",
      "highlights.lede": "GPU na barra, memória usado/total, popover em abas e tokens de IA — os destaques do caminho até a 2.5.",
      "highlights.gpuTitle": "GPU na barra",
      "highlights.gpuBody": "Uso do processador gráfico em tempo real, lido direto do sistema — novidade da 2.4.",
      "highlights.usedtotalTitle": "Memória usado/total",
      "highlights.usedtotalBody": "A barra mostra a memória usada sobre o total do seu Mac, colorida pela pressão — App Memory e Pressão continuam como opções.",
      "highlights.monoTitle": "Barra monocromática",
      "highlights.monoBody": "Valores no estilo nativo do macOS: a cor padrão do sistema, com vermelho reservado só para o estado crítico.",
      "highlights.popoverTitle": "Popover em abas",
      "highlights.popoverBody": "Um popover redesenhado, em cartões e abas — CPU, memória, rede/disco e tokens, cada um com seus detalhes.",
      "highlights.tokensTitle": "Tokens de IA",
      "highlights.tokensBody": "Acompanhe o consumo e o custo estimado de Claude Code e Codex — ritmo por hora e projeção do dia.",
      "highlights.ramTitle": "Memória detalhada",
      "highlights.ramBody": "Uma divisão no estilo Monitor de Atividade: memória de apps, swap e pressão do kernel, ao vivo.",
      "highlights.netdiskTitle": "Rede e disco a fundo",
      "highlights.netdiskBody": "Cartões expansíveis com leitura/escrita e download/upload, mais os totais da sessão atual.",
      "highlights.batteryTitle": "Bateria",
      "highlights.batteryBody": "Carga, fonte de energia e condição da bateria direto na barra — em notebooks.",
      "highlights.tempTitle": "Temperatura",
      "highlights.tempBody": "Estado térmico em °C, direto dos sensores do Apple Silicon.",
      "highlights.rateTitle": "Ritmo ajustável",
      "highlights.rateBody": "Escolha a frequência de atualização e economize energia quando quiser.",
      "highlights.updateTitle": "Atualização automática",
      "highlights.updateBody": "Novas versões assinadas chegam pelo próprio app, sem disparar o Gatekeeper de novo.",

      "demo.eyebrow": "Experimente",
      "demo.title": "Explore o popover, aba por aba.",
      "demo.lede": "Clique nas abas para ver o detalhe de cada métrica — é o popover real da série 2.",
      "demo.tabCPU": "CPU",
      "demo.tabRAM": "Memória",
      "demo.tabNet": "Rede/Disco",
      "demo.tabAI": "Tokens",
      "demo.altCPU": "Aba CPU do popover mostrando o uso atual e os principais processos",
      "demo.altRAM": "Aba de memória mostrando a divisão de apps, swap e pressão do kernel",
      "demo.altNet": "Aba de rede e disco com leitura/escrita, download/upload e totais da sessão",
      "demo.altAI": "Aba de tokens de IA com ritmo de consumo, custo em dólar e projeção",
      "demo.descCPU": "Os processos que mais pesam, em tempo real.",
      "demo.descRAM": "Apps, swap e pressão do kernel, no estilo Monitor de Atividade.",
      "demo.descNet": "Leitura/escrita e download/upload, com totais da sessão.",
      "demo.descAI": "Ritmo, custo estimado e projeção do dia.",

      "features.eyebrow": "Tudo que ele mostra",
      "features.title": "Oito métricas, uma barra de menus.",
      "features.cpuTitle": "CPU",
      "features.cpuBody": "Uso atual e os processos que mais consomem, no popover.",
      "features.gpuTitle": "GPU",
      "features.gpuBody": "Uso do processador gráfico, em tempo real.",
      "features.ramTitle": "Memória",
      "features.ramBody": "Memória de apps, pressão e swap, com mini-gráfico.",
      "features.netTitle": "Rede",
      "features.netBody": "Download e upload ao vivo, em formato compacto.",
      "features.tempTitle": "Temperatura",
      "features.tempBody": "°C com cor por estado térmico, no Apple Silicon.",
      "features.diskTitle": "Disco",
      "features.diskBody": "Luz de atividade do SSD com leitura e escrita.",
      "features.batteryTitle": "Bateria",
      "features.batteryBody": "Carga, fonte de energia e condição em notebooks.",
      "features.tokensTitle": "Tokens de IA",
      "features.tokensBody": "Consumo e custo de Claude Code e Codex.",

      "privacy.eyebrow": "Privacidade primeiro",
      "privacy.title": "Os dados não saem do seu Mac.",
      "privacy.body": "O Mac Metrics View lê CPU, memória, rede, disco e os logs locais de IA no seu Mac. Sem login, sem telemetria e sem serviços externos para funcionar.",
      "privacy.li1": "Sem conta de usuário",
      "privacy.li2": "Sem analytics dentro do app",
      "privacy.li3": "Leitura 100% local — nada sai pela rede",

      "download.eyebrow": "Download",
      "download.title": "Baixe a versão 2.5.",
      "download.body": "Para macOS 14 ou superior em Macs com Apple Silicon. Na primeira abertura o macOS pode pedir confirmação por ser um app ainda não notarizado — depois disso, ele se mantém atualizado sozinho.",
      "download.cta": "Baixar MacMetricsView-2.5.0.zip",
      "download.meta": "≈ 2 MB · macOS 14+ · Apple Silicon · grátis e de código aberto",

      "firstrun.eyebrow": "Primeira abertura",
      "firstrun.title": "Viu “MacMetricsView não foi aberto”? É esperado.",
      "firstrun.body": "Como o app ainda não é notarizado pela Apple, o macOS bloqueia a primeira execução por precaução — não é um erro nem sinal de malware. Libere o app uma única vez assim:",
      "firstrun.s1Title": "Clique em “OK”",
      "firstrun.s1Body": "No aviso, escolha “OK” — nunca “Mover para o Lixo”. Isso apenas fecha o alerta sem apagar o app.",
      "firstrun.s2Title": "Abra Privacidade e Segurança",
      "firstrun.s2Body": "Em Ajustes do Sistema → Privacidade e Segurança, role até “MacMetricsView foi bloqueado” e clique em “Abrir Mesmo Assim”.",
      "firstrun.s3Title": "Confirme e abra",
      "firstrun.s3Body": "Autentique com Touch ID ou senha e clique em “Abrir”. Só é preciso fazer isso uma vez.",
      "firstrun.alt": "No macOS Ventura ou anterior: clique com o botão direito (ou Control+clique) no app e escolha “Abrir” — pule os passos 2 e 3 acima.",
      "firstrun.update": "Isso só vale para esta primeira instalação manual. As próximas versões chegam pelo próprio app, com atualizações assinadas que não disparam o Gatekeeper de novo.",

      "timeline.eyebrow": "Linha do tempo",
      "timeline.title": "De 1.0 a 2.5.",
      "timeline.lede": "O caminho até a versão 2.5, em resumo.",
      "timeline.v25Title": "2.5 — Mais leve do que nunca",
      "timeline.v25Body": "Rodada de otimizações de CPU, energia e I/O — o monitor pesa ainda menos no Mac que ele mede.",
      "timeline.v24Title": "2.4 — GPU na barra de menus",
      "timeline.v24Body": "Novo medidor de uso do processador gráfico e arquitetura interna reorganizada para as próximas métricas.",
      "timeline.v23Title": "2.3 — Só Apple Silicon e tema automático",
      "timeline.v23Body": "Suporte exclusivo a Macs com chip Apple (M); código de compatibilidade com Intel removido. Sugestão automática de tema claro/escuro conforme a luz do ambiente.",
      "timeline.v22Title": "2.2 — Mais leve e foco em Claude e Codex",
      "timeline.v22Body": "Amostragem fora da thread principal (menos energia), aviso de acessibilidade só no popover e tokens de IA focados em Claude Code e Codex.",
      "timeline.v21Title": "2.1 — Memória usado/total e barra monocromática",
      "timeline.v21Body": "RAM na barra agora mostra usado/total com cor por pressão; valores monocromáticos no estilo nativo, vermelho só no crítico.",
      "timeline.v20Title": "2.0 — Popover em abas e suite completa",
      "timeline.v20Body": "Popover redesenhado, tokens de IA (Claude, Codex e Gemini), memória detalhada, rede/disco, bateria e temperatura.",
      "timeline.v18Title": "1.8 — Ritmo de tokens",
      "timeline.v18Body": "Ritmo por hora e projeção diária do consumo.",
      "timeline.v17Title": "1.7 — Custo em dólar",
      "timeline.v17Body": "Custo estimado do uso de IA, por modelo.",
      "timeline.v16Title": "1.6 — Tokens do Codex",
      "timeline.v16Body": "Leitura dos logs locais do Codex (ChatGPT).",
      "timeline.v15Title": "1.5 — Medidor de tokens",
      "timeline.v15Body": "Consumo do Claude Code na barra e no popover.",
      "timeline.v14Title": "1.4 — Popover repensado",
      "timeline.v14Body": "Layout mais limpo, com todas as métricas visíveis.",
      "timeline.v13Title": "1.3 — Luz do SSD",
      "timeline.v13Body": "LED de atividade do disco e detalhes de leitura/escrita.",
      "timeline.v10Title": "1.0 — Primeira versão estável",
      "timeline.v10Body": "Modo limpeza, abrir ao iniciar e interface em PT/EN.",

      "footer.tagline": "Versão 2.5 para macOS",
      "footer.rights": "Código aberto · Licença MIT",
      "footer.github": "GitHub"
    },
    en: {
      "nav.whatsnew": "What's new",
      "nav.demo": "Demo",
      "nav.features": "Features",
      "nav.privacy": "Privacy",
      "nav.download": "Download",

      "hero.eyebrow": "Version 2.5 for macOS",
      "hero.title": "Your whole Mac, in the menu bar.",
      "hero.lede": "CPU, GPU, memory, network, temperature, disk, battery, and AI tokens — all at a glance, without opening Activity Monitor.",
      "hero.cta": "Download 2.5",
      "hero.secondary": "See what's new",
      "hero.note": "No account. No telemetry. Local-only system readings.",
      "hero.altMenu": "Mac Metrics View in the macOS menu bar showing CPU, RAM, network, temperature, disk, and battery",

      "sticky.label": "Mac Metrics View 2.5",
      "sticky.cta": "Download",

      "metric.cpu": "usage and processes",
      "metric.gpu": "graphics chip usage",
      "metric.ram": "apps, pressure, and swap",
      "metric.net": "download and upload",
      "metric.temp": "thermal state",
      "metric.disk": "read and write",
      "metric.bat": "charge and power",
      "metric.ai": "tokens and cost",

      "highlights.eyebrow": "Series 2 highlights",
      "highlights.title": "Every release, a leap.",
      "highlights.lede": "GPU in the bar, used/total memory, a tabbed popover, and AI tokens — the highlights on the road to 2.5.",
      "highlights.gpuTitle": "GPU in the bar",
      "highlights.gpuBody": "Real-time graphics processor usage, read straight from the system — new in 2.4.",
      "highlights.usedtotalTitle": "Used/total memory",
      "highlights.usedtotalBody": "The menu bar shows memory used over your Mac's total, tinted by pressure — App Memory and Pressure stay as options.",
      "highlights.monoTitle": "Monochrome menu bar",
      "highlights.monoBody": "Native macOS values: the standard system color, with red reserved for the critical state only.",
      "highlights.popoverTitle": "Tabbed popover",
      "highlights.popoverBody": "A redesigned popover in cards and tabs — CPU, memory, network/disk, and tokens, each with its own detail.",
      "highlights.tokensTitle": "AI tokens",
      "highlights.tokensBody": "Track usage and estimated cost for Claude Code and Codex — hourly pace and a daily projection.",
      "highlights.ramTitle": "Detailed memory",
      "highlights.ramBody": "An Activity-Monitor-style breakdown: app memory, swap, and kernel pressure, live.",
      "highlights.netdiskTitle": "Network and disk in depth",
      "highlights.netdiskBody": "Expandable cards with read/write and download/upload, plus current session totals.",
      "highlights.batteryTitle": "Battery",
      "highlights.batteryBody": "Charge, power source, and battery condition right in the menu bar — on laptops.",
      "highlights.tempTitle": "Temperature",
      "highlights.tempBody": "Thermal state in °C, straight from the Apple Silicon sensors.",
      "highlights.rateTitle": "Adjustable pace",
      "highlights.rateBody": "Pick the update rate and save energy whenever you want.",
      "highlights.updateTitle": "Automatic updates",
      "highlights.updateBody": "New signed versions arrive through the app itself, without re-triggering Gatekeeper.",

      "demo.eyebrow": "Try it",
      "demo.title": "Explore the popover, tab by tab.",
      "demo.lede": "Click the tabs to see each metric's detail — it's the real series-2 popover.",
      "demo.tabCPU": "CPU",
      "demo.tabRAM": "Memory",
      "demo.tabNet": "Network/Disk",
      "demo.tabAI": "Tokens",
      "demo.altCPU": "Popover CPU tab showing current usage and the top processes",
      "demo.altRAM": "Memory tab showing the app, swap, and kernel-pressure breakdown",
      "demo.altNet": "Network and disk tab with read/write, download/upload, and session totals",
      "demo.altAI": "AI tokens tab with usage pace, dollar cost, and projection",
      "demo.descCPU": "The heaviest processes, in real time.",
      "demo.descRAM": "Apps, swap, and kernel pressure, Activity-Monitor style.",
      "demo.descNet": "Read/write and download/upload, with session totals.",
      "demo.descAI": "Pace, estimated cost, and a daily projection.",

      "features.eyebrow": "Everything it shows",
      "features.title": "Eight metrics, one menu bar.",
      "features.cpuTitle": "CPU",
      "features.cpuBody": "Current usage and the top-consuming processes, in the popover.",
      "features.gpuTitle": "GPU",
      "features.gpuBody": "Graphics processor usage, in real time.",
      "features.ramTitle": "Memory",
      "features.ramBody": "App memory, pressure, and swap, with a sparkline.",
      "features.netTitle": "Network",
      "features.netBody": "Live download and upload, in a compact format.",
      "features.tempTitle": "Temperature",
      "features.tempBody": "°C with a color per thermal state, on Apple Silicon.",
      "features.diskTitle": "Disk",
      "features.diskBody": "An SSD activity light with read and write.",
      "features.batteryTitle": "Battery",
      "features.batteryBody": "Charge, power source, and condition on laptops.",
      "features.tokensTitle": "AI tokens",
      "features.tokensBody": "Usage and cost for Claude Code and Codex.",

      "privacy.eyebrow": "Privacy first",
      "privacy.title": "Your data never leaves your Mac.",
      "privacy.body": "Mac Metrics View reads CPU, memory, network, disk, and local AI logs on your Mac. No login, no telemetry, and no external services to work.",
      "privacy.li1": "No user account",
      "privacy.li2": "No in-app analytics",
      "privacy.li3": "100% local reads — nothing leaves over the network",

      "download.eyebrow": "Download",
      "download.title": "Download version 2.5.",
      "download.body": "For macOS 14 or later on Apple Silicon Macs. On first launch macOS may ask for confirmation because the app isn't notarized yet — after that, it keeps itself up to date.",
      "download.cta": "Download MacMetricsView-2.5.0.zip",
      "download.meta": "≈ 2 MB · macOS 14+ · Apple Silicon · free and open source",

      "firstrun.eyebrow": "First launch",
      "firstrun.title": "See “MacMetricsView Was Not Opened”? That's expected.",
      "firstrun.body": "Because the app isn't notarized by Apple yet, macOS blocks the first launch as a precaution — it's not an error or a sign of malware. Allow the app once like this:",
      "firstrun.s1Title": "Click “OK”",
      "firstrun.s1Body": "In the alert, choose “OK” — never “Move to Trash”. This just dismisses the warning without deleting the app.",
      "firstrun.s2Title": "Open Privacy & Security",
      "firstrun.s2Body": "In System Settings → Privacy & Security, scroll to “MacMetricsView was blocked” and click “Open Anyway”.",
      "firstrun.s3Title": "Confirm and open",
      "firstrun.s3Body": "Authenticate with Touch ID or your password and click “Open”. You only need to do this once.",
      "firstrun.alt": "On macOS Ventura or earlier: right-click (or Control-click) the app and choose “Open” — skip steps 2 and 3 above.",
      "firstrun.update": "This only applies to this first manual install. Later versions arrive through the app itself, as signed updates that don't re-trigger Gatekeeper.",

      "timeline.eyebrow": "Timeline",
      "timeline.title": "From 1.0 to 2.5.",
      "timeline.lede": "The road to version 2.5, in brief.",
      "timeline.v25Title": "2.5 — Lighter than ever",
      "timeline.v25Body": "A round of CPU, energy, and I/O optimizations — the monitor weighs even less on the Mac it measures.",
      "timeline.v24Title": "2.4 — GPU in the menu bar",
      "timeline.v24Body": "A new graphics-usage meter and a reorganized internal architecture for the metrics to come.",
      "timeline.v23Title": "2.3 — Apple Silicon only and automatic theme",
      "timeline.v23Body": "Exclusive support for Apple-chip Macs (M-series); Intel compatibility code removed. Automatic light/dark theme suggestion based on ambient light.",
      "timeline.v22Title": "2.2 — Lighter, focused on Claude and Codex",
      "timeline.v22Body": "Sampling moved off the main thread (less energy), the accessibility notice now lives only in the popover, and AI tokens focus on Claude Code and Codex.",
      "timeline.v21Title": "2.1 — Used/total memory and a monochrome menu bar",
      "timeline.v21Body": "Menu-bar RAM now shows used/total tinted by memory pressure; values are native monochrome, with red reserved for the critical state.",
      "timeline.v20Title": "2.0 — Tabbed popover and a complete suite",
      "timeline.v20Body": "Redesigned popover, AI tokens (Claude, Codex, and Gemini), detailed memory, network/disk, battery, and temperature.",
      "timeline.v18Title": "1.8 — Token pace",
      "timeline.v18Body": "Hourly pace and a daily projection of your usage.",
      "timeline.v17Title": "1.7 — Cost in dollars",
      "timeline.v17Body": "Estimated cost of AI usage, per model.",
      "timeline.v16Title": "1.6 — Codex tokens",
      "timeline.v16Body": "Reads Codex (ChatGPT) local logs.",
      "timeline.v15Title": "1.5 — Token meter",
      "timeline.v15Body": "Claude Code usage in the menu bar and popover.",
      "timeline.v14Title": "1.4 — Rethought popover",
      "timeline.v14Body": "A cleaner layout with every metric visible.",
      "timeline.v13Title": "1.3 — SSD light",
      "timeline.v13Body": "Disk activity LED and read/write detail.",
      "timeline.v10Title": "1.0 — First stable release",
      "timeline.v10Body": "Cleaning mode, open at login, and a PT/EN interface.",

      "footer.tagline": "Version 2.5 for macOS",
      "footer.rights": "Open source · MIT License",
      "footer.github": "GitHub"
    }
  };

  var STORAGE_KEY = "mmv-lang";

  var SITE_BASE = "https://patrickonofre.github.io/mac-metrics-view/";

  function resolveInitial() {
    var q = null;
    try { q = new URLSearchParams(location.search).get("lang"); } catch (e) {}
    if (q === "pt" || q === "en") return q;
    var stored = null;
    try { stored = localStorage.getItem(STORAGE_KEY); } catch (e) {}
    if (stored === "pt" || stored === "en") return stored;
    var nav = (navigator.language || navigator.userLanguage || "en").toLowerCase();
    return nav.indexOf("pt") === 0 ? "pt" : "en";
  }

  // Keep canonical / og:url / og:locale in sync with the rendered language so
  // JS-rendering crawlers see a self-consistent hreflang cluster.
  function syncLangMeta(lang, updateUrl) {
    var url = SITE_BASE + "?lang=" + lang;
    var canon = document.querySelector('link[rel="canonical"]');
    if (canon) canon.setAttribute("href", url);
    var ogUrl = document.querySelector('meta[property="og:url"]');
    if (ogUrl) ogUrl.setAttribute("content", url);
    var ogLocale = document.querySelector('meta[property="og:locale"]');
    if (ogLocale) ogLocale.setAttribute("content", lang === "pt" ? "pt_BR" : "en_US");
    var ogLocaleAlt = document.querySelector('meta[property="og:locale:alternate"]');
    if (ogLocaleAlt) ogLocaleAlt.setAttribute("content", lang === "pt" ? "en_US" : "pt_BR");
    if (updateUrl) {
      try { history.replaceState(null, "", url); } catch (e) {}
    }
  }

  function apply(lang, updateUrl) {
    var dict = STRINGS[lang] || STRINGS.en;

    document.querySelectorAll("[data-i18n]").forEach(function (el) {
      var v = dict[el.getAttribute("data-i18n")];
      if (v != null) el.textContent = v;
    });
    document.querySelectorAll("[data-i18n-alt]").forEach(function (el) {
      var v = dict[el.getAttribute("data-i18n-alt")];
      if (v != null) el.setAttribute("alt", v);
    });

    document.documentElement.lang = lang === "pt" ? "pt-BR" : "en";
    syncLangMeta(lang, updateUrl);

    document.querySelectorAll("[data-lang-option]").forEach(function (btn) {
      var active = btn.getAttribute("data-lang-option") === lang;
      btn.setAttribute("aria-pressed", active ? "true" : "false");
      btn.classList.toggle("is-active", active);
    });

    try { localStorage.setItem(STORAGE_KEY, lang); } catch (e) {}
  }

  function init() {
    apply(resolveInitial(), false);
    document.querySelectorAll("[data-lang-option]").forEach(function (btn) {
      btn.addEventListener("click", function () {
        apply(btn.getAttribute("data-lang-option"), true);
      });
    });
  }

  // Run the DOM wiring only in a browser; stay inert (and requirable) in Node so
  // the parity check / tests can import STRINGS without a DOM.
  if (typeof document !== "undefined") {
    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", init);
    } else {
      init();
    }
  }

  // Expose the dictionary for the parity check / tests (no-op in the browser).
  if (typeof module !== "undefined" && module.exports) {
    module.exports = { STRINGS: STRINGS };
  }
})();
