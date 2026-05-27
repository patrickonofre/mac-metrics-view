// Lightweight i18n for the static site. Mirrors the app's PT/EN support.
// Text nodes carry data-i18n="key"; image alts carry data-i18n-alt="key".
(function () {
  "use strict";

  var STRINGS = {
    pt: {
      "nav.news": "Novidades",
      "nav.features": "Recursos",
      "nav.privacy": "Privacidade",
      "nav.firstrun": "Abrir o app",
      "nav.download": "Download",

      "hero.eyebrow": "Versão 1.0 para macOS",
      "hero.title": "CPU, RAM e rede direto na barra de menus.",
      "hero.lede": "Um app nativo e compacto para entender a pressão do seu Mac sem abrir o Monitor de Atividade.",
      "hero.cta": "Baixar 1.0",
      "hero.secondary": "Ver novidades",
      "hero.note": "Sem conta. Sem telemetria. Leitura local dos indicadores do sistema.",
      "hero.altMenu": "Mac Metrics View exibindo CPU, RAM, rede e temperatura na barra de menus do macOS",
      "hero.altPopover": "Popover do Mac Metrics View com CPU, RAM, rede, temperatura e controles de exibição",

      "metric.cpu": "uso atual",
      "metric.ram": "memória em GB",
      "metric.net": "download e upload",
      "metric.temp": "estado térmico",

      "news.eyebrow": "Versão 1.0",
      "news.title": "A primeira versão estável, com tudo no lugar.",
      "news.cleanTitle": "Modo limpeza",
      "news.cleanBody": "Trave teclado e trackpad por 15s a 5min para limpar a tela sem disparar cliques ou teclas. Requer permissão de Acessibilidade do macOS.",
      "news.loginTitle": "Abrir ao inicializar",
      "news.loginBody": "Ative no popover para o Mac Metrics View abrir sozinho ao iniciar a sessão no macOS. Reversível a qualquer momento.",
      "news.langTitle": "Português e inglês",
      "news.langBody": "A interface acompanha o idioma do sistema, em português ou inglês, sem configuração manual.",

      "features.eyebrow": "Feito para ficar quieto",
      "features.title": "Monitoramento de sistema sem interromper seu fluxo.",
      "features.f1Title": "Barra de menus compacta",
      "features.f1Body": "Veja CPU, RAM e rede perto do relógio do macOS, com indicadores curtos e fáceis de escanear.",
      "features.f2Title": "Popover nativo",
      "features.f2Body": "Clique no indicador para abrir detalhes recentes, alternar métricas e ajustar a exibição.",
      "features.f3Title": "Controle por métrica",
      "features.f3Body": "Mostre apenas o que importa. Métricas ocultas param de coletar novos dados.",
      "features.f4Title": "Visual do macOS",
      "features.f4Body": "Interface discreta, responsiva a claro e escuro, pensada para parecer parte do sistema.",
      "features.f5Title": "Atualizações automáticas",
      "features.f5Body": "O app verifica novas versões e instala atualizações assinadas no lugar, sem precisar voltar aqui. Você decide quando instalar, e os updates não disparam o aviso do Gatekeeper de novo.",

      "privacy.eyebrow": "Privacidade primeiro",
      "privacy.title": "Os dados não saem do seu Mac.",
      "privacy.body": "O Mac Metrics View lê CPU, memória e contadores locais de rede. Ele não exige login, não envia telemetria e não depende de serviços externos para funcionar.",
      "privacy.li1": "Sem conta de usuário",
      "privacy.li2": "Sem analytics dentro do app",
      "privacy.li3": "Sem chamadas externas para monitorar a rede",

      "download.eyebrow": "Download",
      "download.title": "Baixe a versão 1.0.",
      "download.body": "Versão 1.0 para macOS (Apple Silicon). Na primeira abertura, o macOS pode pedir confirmação por ser um app ainda não notarizado — depois disso, o app se mantém atualizado sozinho.",
      "download.cta": "Baixar MacMetricsView-1.0.3.zip",

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

      "footer.tagline": "Versão 1.0 para macOS"
    },
    en: {
      "nav.news": "What's new",
      "nav.features": "Features",
      "nav.privacy": "Privacy",
      "nav.firstrun": "Open the app",
      "nav.download": "Download",

      "hero.eyebrow": "Version 1.0 for macOS",
      "hero.title": "CPU, RAM, and network right in the menu bar.",
      "hero.lede": "A compact, native app to read your Mac's load at a glance — without opening Activity Monitor.",
      "hero.cta": "Download 1.0",
      "hero.secondary": "See what's new",
      "hero.note": "No account. No telemetry. Local-only system readings.",
      "hero.altMenu": "Mac Metrics View showing CPU, RAM, network, and temperature in the macOS menu bar",
      "hero.altPopover": "Mac Metrics View popover with CPU, RAM, network, temperature, and display controls",

      "metric.cpu": "current usage",
      "metric.ram": "memory in GB",
      "metric.net": "download and upload",
      "metric.temp": "thermal state",

      "news.eyebrow": "Version 1.0",
      "news.title": "The first stable release, with everything in place.",
      "news.cleanTitle": "Cleaning mode",
      "news.cleanBody": "Lock the keyboard and trackpad for 15s to 5min so you can wipe the screen without triggering clicks or keys. Requires macOS Accessibility permission.",
      "news.loginTitle": "Open at login",
      "news.loginBody": "Turn it on in the popover and Mac Metrics View opens itself when you sign in to macOS. Reversible anytime.",
      "news.langTitle": "Portuguese and English",
      "news.langBody": "The interface follows the system language, in Portuguese or English, with no manual setup.",

      "features.eyebrow": "Built to stay quiet",
      "features.title": "System monitoring that never interrupts your flow.",
      "features.f1Title": "Compact menu bar",
      "features.f1Body": "See CPU, RAM, and network next to the macOS clock, with short indicators that are easy to scan.",
      "features.f2Title": "Native popover",
      "features.f2Body": "Click the indicator to open recent detail, toggle metrics, and adjust the display.",
      "features.f3Title": "Per-metric control",
      "features.f3Body": "Show only what matters. Hidden metrics stop collecting new data.",
      "features.f4Title": "macOS look and feel",
      "features.f4Body": "A discreet interface that responds to light and dark, designed to feel part of the system.",
      "features.f5Title": "Automatic updates",
      "features.f5Body": "The app checks for new versions and installs signed updates in place — no need to come back here. You decide when to install, and updates don't re-trigger Gatekeeper.",

      "privacy.eyebrow": "Privacy first",
      "privacy.title": "Your data never leaves your Mac.",
      "privacy.body": "Mac Metrics View reads CPU, memory, and local network counters. It requires no login, sends no telemetry, and depends on no external services to work.",
      "privacy.li1": "No user account",
      "privacy.li2": "No in-app analytics",
      "privacy.li3": "No external calls to monitor the network",

      "download.eyebrow": "Download",
      "download.title": "Download version 1.0.",
      "download.body": "Version 1.0 for macOS (Apple Silicon). On first launch, macOS may ask for confirmation because the app is not yet notarized — after that, the app keeps itself up to date.",
      "download.cta": "Download MacMetricsView-1.0.3.zip",

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

      "footer.tagline": "Version 1.0 for macOS"
    }
  };

  var STORAGE_KEY = "mmv-lang";

  function resolveInitial() {
    var stored = null;
    try { stored = localStorage.getItem(STORAGE_KEY); } catch (e) {}
    if (stored === "pt" || stored === "en") return stored;
    var nav = (navigator.language || navigator.userLanguage || "en").toLowerCase();
    return nav.indexOf("pt") === 0 ? "pt" : "en";
  }

  function apply(lang) {
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

    document.querySelectorAll("[data-lang-option]").forEach(function (btn) {
      var active = btn.getAttribute("data-lang-option") === lang;
      btn.setAttribute("aria-pressed", active ? "true" : "false");
      btn.classList.toggle("is-active", active);
    });

    try { localStorage.setItem(STORAGE_KEY, lang); } catch (e) {}
  }

  function init() {
    apply(resolveInitial());
    document.querySelectorAll("[data-lang-option]").forEach(function (btn) {
      btn.addEventListener("click", function () {
        apply(btn.getAttribute("data-lang-option"));
      });
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
