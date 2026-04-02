from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import inch
from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle


ROOT = Path("/Users/avrohom/Downloads/BlackHaven")
OUTPUT = ROOT / "output" / "pdf" / "blackhaven_app_summary.pdf"


def bullet(text: str) -> str:
    return f"• {text}"


styles = getSampleStyleSheet()
styles.add(
    ParagraphStyle(
        name="TitleSmall",
        parent=styles["Title"],
        fontName="Helvetica-Bold",
        fontSize=18.5,
        leading=22,
        textColor=colors.HexColor("#14213D"),
        spaceAfter=4,
    )
)
styles.add(
    ParagraphStyle(
        name="Section",
        parent=styles["Heading2"],
        fontName="Helvetica-Bold",
        fontSize=10.2,
        leading=12,
        textColor=colors.HexColor("#9A3412"),
        spaceBefore=3,
        spaceAfter=3,
    )
)
styles.add(
    ParagraphStyle(
        name="BodyTight",
        parent=styles["BodyText"],
        fontName="Helvetica",
        fontSize=8.8,
        leading=10.8,
        alignment=TA_LEFT,
        textColor=colors.HexColor("#1F2937"),
        spaceAfter=2,
    )
)
styles.add(
    ParagraphStyle(
        name="BulletTight",
        parent=styles["BodyText"],
        fontName="Helvetica",
        fontSize=8.3,
        leading=10.1,
        leftIndent=8,
        firstLineIndent=-6,
        textColor=colors.HexColor("#1F2937"),
        spaceAfter=1.2,
    )
)
styles.add(
    ParagraphStyle(
        name="FootNote",
        parent=styles["BodyText"],
        fontName="Helvetica-Oblique",
        fontSize=7.4,
        leading=8.7,
        textColor=colors.HexColor("#4B5563"),
        spaceBefore=3,
    )
)


story = [
    Paragraph("BlackHaven / Atlas Masa App Summary", styles["TitleSmall"]),
    Paragraph(
        "One-page summary based only on repo evidence in <b>/Users/avrohom/Downloads/BlackHaven</b>.",
        styles["BodyTight"],
    ),
    Spacer(1, 0.06 * inch),
]


left = [
    Paragraph("What It Is", styles["Section"]),
    Paragraph(
        "A multi-platform, local-first AI app ecosystem with web plus native iOS, macOS, Android, and Windows clients. "
        "Repo docs describe the website as the entry/sales layer and the native apps as the actual planning, memory, queue, and execution product.",
        styles["BodyTight"],
    ),
    Paragraph("Who It’s For", styles["Section"]),
    Paragraph(
        "Primary persona: people who want privacy-conscious help organizing life, work, and mobility with local-first AI. "
        "A narrower named ICP or demographic profile was <b>Not found in repo.</b>",
        styles["BodyTight"],
    ),
    Paragraph("What It Does", styles["Section"]),
]

feature_bullets = [
    "Command Center views for daily, mid-term, and long-horizon planning.",
    "Adaptive survey/onboarding for profile, intent, and mobility capture.",
    "Notes, memory ingestion, and local memory wipe controls.",
    "Prompt queue with local reasoning workers and fallback behavior.",
    "Execution streams that turn plans into next actions and suggestions.",
    "Apple, Google, and passkey-based access flows across apps.",
    "Shared backend plus optional local LLM runtime across platforms.",
]
left.extend(Paragraph(bullet(item), styles["BulletTight"]) for item in feature_bullets)

right = [
    Paragraph("How It Works", styles["Section"]),
    Paragraph(
        "<b>UI layer:</b> Next.js website at repo root (<b>app/</b>, <b>components/</b>) plus native apps in "
        "<b>ios-app/</b>, <b>macos-app/</b>, <b>android-app/</b>, and <b>windows-app/</b>.",
        styles["BodyTight"],
    ),
    Paragraph(
        "<b>Service layer:</b> Rust <b>atlas-concierge/</b> workspace with crates for core models/policies, retrieval, ML, agents, storage, observability, API, CLI, and tests. The API uses Axum and supports in-memory or SQLite persistence.",
        styles["BodyTight"],
    ),
    Paragraph(
        "<b>Client/runtime flow:</b> user input enters web/native UI, then goes either to local runtime or the shared backend (<b>/v1/chat</b>, auth, memory, billing). Android docs show Room/DataStore/WorkManager; Windows docs show encrypted local JSON state + DPAPI; Apple docs show runtime config in UserDefaults and secrets in Keychain.",
        styles["BodyTight"],
    ),
    Paragraph(
        "<b>Local-first inference:</b> repo docs show local LLM endpoints or managed Ollama/Rust reasoners first, with deterministic fallback when services are unavailable.",
        styles["BodyTight"],
    ),
    Paragraph("How To Run", styles["Section"]),
]

run_bullets = [
    "From repo root: `npm install`, `cp .env.example .env.local`, `npm run dev`, then open `http://localhost:3000`.",
    "Optional backend: `cd atlas-concierge`, `cp .env.example .env`, load env vars, run `cargo run -p atlas-api`, then check `/health` on port `8080`.",
    "Native app launch steps are documented separately in the platform READMEs.",
    "A single full-stack bootstrap command was <b>Not found in repo.</b>",
]
right.extend(Paragraph(bullet(item), styles["BulletTight"]) for item in run_bullets)
right.append(
    Paragraph(
        "Evidence: <b>README.md</b>, <b>package.json</b>, <b>atlas-concierge/README.md</b>, <b>atlas-concierge/docs/RUNBOOK.md</b>, and platform READMEs.",
        styles["FootNote"],
    )
)

table = Table([[left, right]], colWidths=[3.5 * inch, 3.5 * inch], hAlign="LEFT")
table.setStyle(
    TableStyle(
        [
            ("VALIGN", (0, 0), (-1, -1), "TOP"),
            ("LEFTPADDING", (0, 0), (-1, -1), 0),
            ("RIGHTPADDING", (0, 0), (-1, -1), 10),
            ("TOPPADDING", (0, 0), (-1, -1), 0),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 0),
            ("LINEAFTER", (0, 0), (0, 0), 0.6, colors.HexColor("#D1D5DB")),
        ]
    )
)
story.append(table)

doc = SimpleDocTemplate(
    str(OUTPUT),
    pagesize=letter,
    leftMargin=0.48 * inch,
    rightMargin=0.48 * inch,
    topMargin=0.42 * inch,
    bottomMargin=0.4 * inch,
)


def draw_page(canvas, _doc):
    canvas.saveState()
    canvas.setStrokeColor(colors.HexColor("#E5E7EB"))
    canvas.setLineWidth(0.8)
    canvas.line(_doc.leftMargin, 10.72 * inch, letter[0] - _doc.rightMargin, 10.72 * inch)
    canvas.setFont("Helvetica", 7.2)
    canvas.setFillColor(colors.HexColor("#6B7280"))
    canvas.drawRightString(letter[0] - _doc.rightMargin, 0.22 * inch, "Generated from repo evidence only")
    canvas.restoreState()


doc.build(story, onFirstPage=draw_page)
print(OUTPUT)
