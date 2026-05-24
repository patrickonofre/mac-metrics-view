from pathlib import Path

from PIL import Image
from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import cm
from reportlab.pdfbase.pdfmetrics import stringWidth
from reportlab.platypus import (
    Flowable,
    Image as RLImage,
    Paragraph,
    PageBreak,
    SimpleDocTemplate,
    Spacer,
    Table,
    TableStyle,
)


ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs" / "product" / "mac-metrics-view-produto.pdf"
SCREENSHOT_POPOVER = Path("/Users/patrickonofre/Desktop/Captura de Tela 2026-05-21 às 20.08.24.png")
SCREENSHOT_BAR = Path("/Users/patrickonofre/Desktop/Captura de Tela 2026-05-21 às 20.08.04.png")

PAGE_W, PAGE_H = A4
MARGIN_X = 1.55 * cm
MARGIN_Y = 1.35 * cm
CONTENT_W = PAGE_W - (2 * MARGIN_X)

INK = colors.HexColor("#191923")
MUTED = colors.HexColor("#5F6370")
BLUE = colors.HexColor("#178CFF")
RED = colors.HexColor("#FF4F45")
PANEL = colors.HexColor("#F4F6FA")
LINE = colors.HexColor("#D8DCE5")
NIGHT = colors.HexColor("#1F2030")


class Pill(Flowable):
    def __init__(self, text, fill=BLUE, text_color=colors.white, pad_x=9, height=18):
        super().__init__()
        self.text = text
        self.fill = fill
        self.text_color = text_color
        self.pad_x = pad_x
        self.height = height
        self.font = "Helvetica-Bold"
        self.size = 7.5
        self.width = stringWidth(text, self.font, self.size) + 2 * pad_x

    def draw(self):
        self.canv.setFillColor(self.fill)
        self.canv.roundRect(0, 0, self.width, self.height, 8, stroke=0, fill=1)
        self.canv.setFillColor(self.text_color)
        self.canv.setFont(self.font, self.size)
        self.canv.drawCentredString(self.width / 2, 5.2, self.text)


def scale_image(path: Path, max_w: float, max_h: float) -> RLImage:
    with Image.open(path) as img:
        w, h = img.size
    scale = min(max_w / w, max_h / h)
    return RLImage(str(path), width=w * scale, height=h * scale)


def styles():
    base = getSampleStyleSheet()
    return {
        "title": ParagraphStyle(
            "Title",
            parent=base["Normal"],
            fontName="Helvetica-Bold",
            fontSize=28,
            leading=31,
            textColor=INK,
            spaceAfter=8,
        ),
        "subtitle": ParagraphStyle(
            "Subtitle",
            parent=base["Normal"],
            fontName="Helvetica",
            fontSize=12.2,
            leading=16,
            textColor=MUTED,
            spaceAfter=13,
        ),
        "section": ParagraphStyle(
            "Section",
            parent=base["Normal"],
            fontName="Helvetica-Bold",
            fontSize=11,
            leading=14,
            textColor=INK,
            spaceBefore=4,
            spaceAfter=7,
        ),
        "body": ParagraphStyle(
            "Body",
            parent=base["Normal"],
            fontName="Helvetica",
            fontSize=9.4,
            leading=13,
            textColor=INK,
            spaceAfter=6,
        ),
        "small": ParagraphStyle(
            "Small",
            parent=base["Normal"],
            fontName="Helvetica",
            fontSize=8.4,
            leading=11.5,
            textColor=MUTED,
        ),
        "card_head": ParagraphStyle(
            "CardHead",
            parent=base["Normal"],
            fontName="Helvetica-Bold",
            fontSize=9.4,
            leading=12,
            textColor=INK,
            spaceAfter=3,
        ),
        "card_body": ParagraphStyle(
            "CardBody",
            parent=base["Normal"],
            fontName="Helvetica",
            fontSize=8.5,
            leading=11.5,
            textColor=MUTED,
        ),
        "quote": ParagraphStyle(
            "Quote",
            parent=base["Normal"],
            fontName="Helvetica-Bold",
            fontSize=15,
            leading=19,
            textColor=colors.white,
            alignment=TA_CENTER,
        ),
        "footer": ParagraphStyle(
            "Footer",
            parent=base["Normal"],
            fontName="Helvetica",
            fontSize=7.5,
            leading=10,
            textColor=colors.HexColor("#868B98"),
            alignment=TA_LEFT,
        ),
    }


def bullet(text, s):
    return Paragraph(f"• {text}", s["body"])


def card(title, text, s):
    return [
        Paragraph(title, s["card_head"]),
        Paragraph(text, s["card_body"]),
    ]


def build():
    s = styles()
    doc = SimpleDocTemplate(
        str(OUT),
        pagesize=A4,
        rightMargin=MARGIN_X,
        leftMargin=MARGIN_X,
        topMargin=MARGIN_Y,
        bottomMargin=MARGIN_Y,
        title="Mac Metrics View - Produto",
        author="Mac Metrics View",
    )

    story = []

    story.append(Pill("VERSAO BETA"))
    story.append(Spacer(1, 10))
    story.append(Paragraph("Mac Metrics View", s["title"]))
    story.append(
        Paragraph(
            "Monitoramento de CPU, RAM e rede direto na barra de menus. "
            "Um sinal constante, discreto e local para entender a saúde do Mac sem abrir o Activity Monitor.",
            s["subtitle"],
        )
    )
    story.append(
        Paragraph(
            "Produto macOS nativo em beta, desenvolvido por <b>Patrick Onofre</b>.",
            s["small"],
        )
    )
    story.append(Spacer(1, 8))

    top_table = Table(
        [
            [
                [
                    Paragraph("O problema", s["section"]),
                    Paragraph(
                        "Quando o Mac fica lento, quente ou preso em uso de memória/rede, o usuário precisa de uma resposta rápida: "
                        "<b>o que está pressionando a máquina agora?</b>",
                        s["body"],
                    ),
                    Paragraph("A solução", s["section"]),
                    Paragraph(
                        "Um app leve de menu bar que mostra métricas essenciais em tempo real e abre um popover com contexto suficiente para decidir o próximo passo.",
                        s["body"],
                    ),
                ],
                scale_image(SCREENSHOT_BAR, CONTENT_W * 0.48, 2.25 * cm),
            ]
        ],
        colWidths=[CONTENT_W * 0.47, CONTENT_W * 0.53],
        hAlign="LEFT",
    )
    top_table.setStyle(
        TableStyle(
            [
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (-1, -1), 0),
                ("RIGHTPADDING", (0, 0), (-1, -1), 0),
                ("TOPPADDING", (0, 0), (-1, -1), 0),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 0),
            ]
        )
    )
    story.append(top_table)
    story.append(Spacer(1, 14))

    value_cards = Table(
        [
            [
                card("Sempre visível", "CPU, RAM e tráfego de rede aparecem onde o usuário já olha: a barra de menus.", s),
                card("Sem fricção", "Clique para abrir detalhes, tendências recentes e controles de visibilidade.", s),
                card("Privado por padrão", "Sem conta, sem telemetry, sem chamadas externas. A leitura acontece localmente.", s),
            ]
        ],
        colWidths=[CONTENT_W / 3] * 3,
    )
    value_cards.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, -1), PANEL),
                ("BOX", (0, 0), (-1, -1), 0.4, LINE),
                ("INNERGRID", (0, 0), (-1, -1), 0.4, LINE),
                ("LEFTPADDING", (0, 0), (-1, -1), 10),
                ("RIGHTPADDING", (0, 0), (-1, -1), 10),
                ("TOPPADDING", (0, 0), (-1, -1), 9),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 9),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
            ]
        )
    )
    story.append(value_cards)
    story.append(Spacer(1, 14))

    story.append(Paragraph("Experiência do produto", s["section"]))
    story.append(
        Table(
            [
                [
                    [
                        bullet("<b>Barra de menus compacta:</b> CPU, RAM em GB e download/upload.", s),
                        bullet("<b>Popover nativo:</b> switches para CPU, RAM, rede e escolha entre ícones ou labels.", s),
                        bullet("<b>Leitura rápida:</b> sparklines simples mostram se a pressão é pontual ou sustentada.", s),
                        bullet("<b>Baixo impacto:</b> métricas ocultas param de coletar amostras.", s),
                    ],
                    scale_image(SCREENSHOT_POPOVER, CONTENT_W * 0.30, 8.0 * cm),
                ]
            ],
            colWidths=[CONTENT_W * 0.57, CONTENT_W * 0.43],
            style=[
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (-1, -1), 0),
                ("RIGHTPADDING", (0, 0), (-1, -1), 0),
            ],
        )
    )

    story.append(Spacer(1, 8))
    story.append(
        Table(
            [[Paragraph("“Uma resposta rápida sobre o estado do Mac, sem transformar monitoramento em mais uma janela.”", s["quote"])]],
            colWidths=[CONTENT_W],
            style=[
                ("BACKGROUND", (0, 0), (-1, -1), NIGHT),
                ("BOX", (0, 0), (-1, -1), 0, NIGHT),
                ("LEFTPADDING", (0, 0), (-1, -1), 18),
                ("RIGHTPADDING", (0, 0), (-1, -1), 18),
                ("TOPPADDING", (0, 0), (-1, -1), 16),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 16),
            ],
        )
    )

    story.append(PageBreak())
    story.append(Paragraph("Público e posicionamento", s["section"]))
    positioning = Table(
        [
            ["Para quem", "Desenvolvedores, power users e usuários de Mac que querem diagnosticar lentidão sem interromper o fluxo."],
            ["Categoria", "Utilitário macOS nativo de monitoramento leve, focado em sinais essenciais."],
            ["Diferencial", "Clareza imediata na menu bar, controle granular do que aparece e operação local por padrão."],
            ["V1", "CPU, RAM, rede, popover com tendências curtas, preferências persistentes e quit action."],
            ["Próximos passos", "Top processos, intervalo configurável, histórico mais rico, disco e opção de iniciar com o sistema."],
        ],
        colWidths=[CONTENT_W * 0.23, CONTENT_W * 0.77],
    )
    positioning.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, -1), colors.white),
                ("BOX", (0, 0), (-1, -1), 0.4, LINE),
                ("INNERGRID", (0, 0), (-1, -1), 0.4, LINE),
                ("FONTNAME", (0, 0), (0, -1), "Helvetica-Bold"),
                ("TEXTCOLOR", (0, 0), (0, -1), INK),
                ("TEXTCOLOR", (1, 0), (1, -1), MUTED),
                ("FONTSIZE", (0, 0), (-1, -1), 8.6),
                ("LEADING", (0, 0), (-1, -1), 11),
                ("LEFTPADDING", (0, 0), (-1, -1), 8),
                ("RIGHTPADDING", (0, 0), (-1, -1), 8),
                ("TOPPADDING", (0, 0), (-1, -1), 7),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 7),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
            ]
        )
    )
    story.append(positioning)
    story.append(Spacer(1, 12))
    story.append(
        Paragraph(
            "Resumo: Mac Metrics View é um produto em versão beta, desenvolvido por Patrick Onofre, para quem quer manter o Mac sob controle sem sair do trabalho principal.",
            s["footer"],
        )
    )

    def paint_page(canvas, _doc):
        canvas.saveState()
        canvas.setFillColor(colors.white)
        canvas.rect(0, 0, PAGE_W, PAGE_H, stroke=0, fill=1)
        canvas.restoreState()

    doc.build(story, onFirstPage=paint_page, onLaterPages=paint_page)


if __name__ == "__main__":
    build()
    print(OUT)
