import Link from "next/link";
import { GuideCard } from "@/components/GuideCard";
import { ProductCard } from "@/components/ProductCard";
import { WhatsAppButton } from "@/components/WhatsAppButton";
import { getAllGuides } from "@/lib/guides";
import { BRAND_SUBTITLE, BRAND_TAGLINE } from "@/lib/site";

const cargoTrailerAdvantages = [
  {
    title: "עלות בסיס נמוכה יותר",
    text: "Trailers מורידים דרמטית את מחיר הפלטפורמה לעומת ואן מלא, גם עבורנו כבונים וגם עבור הלקוח הסופי."
  },
  {
    title: "מודולריות ותחזוקה",
    text: "אפשר להפריד בין יחידת המגורים ליחידת הגרירה, לשדרג בהדרגה, ולתקן או להחליף חלקים בלי להשבית את כל המערכת."
  },
  {
    title: "גמישות תפעולית",
    text: "מי שכבר מחזיק רכב גרירה מתאים יכול להיכנס למודל במחיר נמוך יותר, ומי שלא - יכול לקבל מסלול התאמה מסודר."
  }
];

const atlasVehicleOsRows = [
  {
    title: "Atlas Vehicle OS / Trailer OS",
    text: "מערכת הפעלה ייעודית ליחידת המגורים: מסכים, חיישנים, מצלמות, מיקרופונים, תאורה, אקלים, מים, חשמל ואוטומציות."
  },
  {
    title: "Operator Console On iPhone",
    text: "The iPhone app should become the approval and exception layer for the business: finance alerts, support escalations, logistics exceptions, and remote operational decisions, not just another passive dashboard."
  },
  {
    title: "Mac War Room For Oversight",
    text: "The macOS app should be the high-context control surface: swarm status, fleet signals, factory timeline review, and cost/control analysis in one operator-grade workspace instead of scattered admin panels."
  },
  {
    title: "Local-first edge node",
    text: "המערכת חייבת לעבוד גם בלי אינטרנט יציב. לכן השליטה הקריטית והאוטומציות נשארות מקומית, ורק שכבות הרחבה עוברות לענן."
  },
  {
    title: "חוויית שליטה טקטילית",
    text: "לא הכול דרך טאץ׳. יהיו גם כפתורים, נובים, סליידרים, triggers וממשק פיזי מדויק לחוויית שימוש בטוחה ויוקרתית יותר."
  }
];

const cadStackRows = [
  {
    title: "Generative CAD Under Constraints",
    text: "Atlas should use AI-assisted CAD as a force multiplier inside real engineering tools: define load, mounting, material, and manufacturing constraints first, then evaluate generated design options."
  },
  {
    title: "Onshape For API + Audit Trail",
    text: "If Atlas wants the cleanest agentic engineering path, Onshape is the strongest commercial control plane: REST endpoints, cloud-native modeling workflows, and version history that preserves who changed what, when, and why."
  },
  {
    title: "Validated CAD Job Schemas",
    text: "A real agentic CAD backend should not send free-form 'design me a whole vehicle' prompts into production APIs. It should compile constrained engineering jobs into validated schemas, then execute them feature-by-feature with explicit dimensions, materials, and export targets."
  },
  {
    title: "Fusion For Cheapest Commercial FEA",
    text: "Autodesk Fusion is the lower-cost commercial path when Atlas needs scripting plus built-in simulation: AI can help generate geometry, then run and compare stress or load cases before the design moves forward."
  },
  {
    title: "FreeCAD For Parametric Manufacturing",
    text: "For zero-license R&D, Atlas can use FreeCAD as the parametric engineering engine: the AI writes Python against a constrained part schema, and geometry updates by changing variables instead of redrawing from scratch."
  },
  {
    title: "Code_Aster For Open Validation",
    text: "Open-source geometry is not enough by itself for safety-critical claims. If Atlas stays on the open stack, it should pair FreeCAD with a real solver such as Code_Aster for structural validation instead of relying on visuals alone."
  },
  {
    title: "Blender For Surface + Visual Work",
    text: "Blender fits the visual and simulation side: complex surfaces, aerodynamic studies, render output, and dashboard visuals, while exact fabrication geometry stays anchored to engineering-grade CAD."
  },
  {
    title: "Native Apple Silicon Visualization",
    text: "For large assemblies, Atlas should use a native macOS visualization layer instead of pretending a browser viewer is enough. Apple Silicon opens the right path for local high-fidelity playback, inspection, and scene updates on the machine the engineer already owns."
  },
  {
    title: "Advanced NVH / Thermal Geometry",
    text: "For complex acoustic, vibration, and cooling components, the stack should support advanced geometry workflows instead of pretending standard CAD alone will solve every hard shape."
  },
  {
    title: "2D Drawings + BOM Automation",
    text: "Manufacturing-ready output means more than pretty 3D renders. It requires fabrication drawings, dimensions, tolerances, GD&T, and bill-of-material discipline for the factory floor."
  },
  {
    title: "Compliance Review Agent",
    text: "AI can review geometry and flag likely FMVSS / UNECE / homologation issues, but it is not the legal sign-off authority. That layer still needs qualified human engineering and compliance review."
  }
];

const readinessRows = [
  "סיווגי נגרר מדויקים: משקל ריק, משקל מלא, tongue weight, ודרישות רישוי/גרירה לכל שוק יעד.",
  "הגדרת tow vehicle אמיתי לכל tier: איזה רכב גורר, איזה margin נשאר, ומה רמת היציבות בכביש ובשטח.",
  "Power stack אמיתי: סוללה, מטען, inverter, solar input, DC distribution, shore power, ופרוטוקול חירום להפעלה בזמן תקלה.",
  "מערכת מים / מים אפורים / אוורור / חום / קירור שעובדת בעולם האמיתי ולא רק ב-render או במסמך קונספט.",
  "שרשרת CAD -> BOM -> 2D drawings -> tolerances -> manufacturing QA שסוגרת את הפער בין רעיון לבין ייצור בפועל.",
  "Traceability אמיתית לכל החלטת תכן: גרסאות, parameters, exports, reviewers, ו-audit trail שאפשר להראות למהנדס מאשר או לרגולטור.",
  "FEA אמיתי לכל רכיב ומבנה קריטי, עם load cases, assumptions, mesh discipline, ודו\"חות שמוכיחים שהמודל לא רק יפה אלא גם שורד.",
  "תהליך איכות מסודר בסגנון ISO / IATF 16949: שינויי תכן, ECOs, בדיקות, ספקים, ותיעוד שלא נשבר כשעוברים מ-R&D לייצור.",
  "יעדי UNECE / Israel MoT ברורים מראש: למשל R29 לחוזק תא נהג, R66 ל-rollover ברכבים רלוונטיים, וראיות בדיקה/סימולציה לכל claim.",
  "לשכבות software / electronics צריך גם functional safety אמיתי. AI יכול לעזור, אבל ISO 26262 דורש הנדסה, בדיקות, והוכחה שיטתית.",
  "אם Atlas הולך על חוויית exploded views / cinematic review, צריך native macOS app אמיתי עם קבצי scene היררכיים, pipeline ל-USD/USDZ, ותקציב חומרה ברור למחשבי Apple Silicon.",
  "אם Atlas רוצה iPhone שמנהל עסק end-to-end, הוא צריך approval gates, exception handling, audit trails, ותיחום ברור למה AI רשאי לעשות לבד ומה תמיד דורש אישור אנושי.",
  "אם Atlas רוצה Mac כ-war room אמיתי, צריך source-of-truth ברור ל-agent status, fleet telemetry, factory timelines, ו-token/cost monitoring במקום אוסף מסכים לא מחוברים.",
  "Sandbox אמיתי לכל קוד Python שנוצר ע\"י AI לפני שהוא נוגע ב-FreeCAD / Blender / קבצי תכן / נתיבי יצוא.",
  "מסלול compliance / homologation אמיתי עם מהנדסים מוסמכים, בדיקות פיזיות, וסקירת FMVSS / UNECE לפני כל טענה של road-legal readiness.",
  "בטיחות, שירות, אחריות, spare parts, SOPs, והדרכת משתמש ברמה שאפשר למסור ללקוח אמיתי בלי לאלתר."
];

export default function HomePage() {
  const guides = getAllGuides().slice(0, 3);

  return (
    <>
      <section className="hero-section">
        <div className="container hero-grid">
          <div>
            <p className="kicker">אטלס</p>
            <h1>
              {BRAND_TAGLINE}
              <span>{BRAND_SUBTITLE}</span>
            </h1>
            <p className="hero-description">
              לא שוכרים רכב. מקבלים חוויית מגורים ותנועה: לינה פרטית, גמישות מלאה, ותכנון טיול חינם
              שמותאם לישראל - מים, נקודות ריקון, מקלחות ולינת לילה חוקית.
            </p>
            <div className="hero-actions">
              <WhatsAppButton text="בדיקת זמינות ב-WhatsApp" />
              <Link href="/packages" className="btn btn-secondary">
                לצפייה בחבילות
              </Link>
            </div>
          </div>

          <aside className="hero-panel" aria-label="ערך מרכזי">
            <h2>מה מקבלים בכל חבילה</h2>
            <ul>
              <li>תכנון מסלול אישי ללא תוספת תשלום</li>
              <li>תכנית מים/מים אפורים חוקית ומעשית</li>
              <li>המלצות לינה מסודרת + תכנית גיבוי</li>
              <li>מדיניות איכות ברורה: ללא עישון</li>
            </ul>
          </aside>
        </div>
      </section>

      <section className="section-shell">
        <div className="container section-stack">
          <h2>למה Cargo Trailers ולא ואנים</h2>
          <p className="section-intro">
            הכיוון הנוכחי של Atlas Masa הוא converted cargo trailers: כדי להוריד עלות בסיס, לבנות מודולרי,
            ולהפוך את תשתית המגורים והעבודה לנגישה יותר גם לנו וגם ללקוח.
          </p>
          <div className="feature-grid">
            {cargoTrailerAdvantages.map((item) => (
              <article key={item.title}>
                <h3>{item.title}</h3>
                <p>{item.text}</p>
              </article>
            ))}
          </div>
        </div>
      </section>

      <section className="section-shell accent-shell">
        <div className="container section-stack">
          <h2>Atlas Vehicle OS לתשתית נגררים חכמה</h2>
          <p className="section-intro">
            המסמך מבקש יותר מ״אתר + אפליקציה״, והוא צודק. הכיוון הוא מערכת Atlas Vehicle OS שתוכננה
            ליחידת מגורים נגררת: חיישנים, מסכים, בקרים פיזיים, זהות משתמש, ואוטומציות ל-Life / Work / Travel.
          </p>
          <div className="feature-grid">
            {atlasVehicleOsRows.map((item) => (
              <article key={item.title}>
                <h3>{item.title}</h3>
                <p>{item.text}</p>
              </article>
            ))}
          </div>
          <article className="notice-card">
            <h3>חשוב: זהו כיוון מוצרי, לא הבטחת מסירה מיידית</h3>
            <p>
              כרגע האתר מציג את מפת המוצר וההנדסה. רכיבי Vehicle OS, חיבורי חיישנים, ו-control deck פיזי
              הם חלק מה-roadmap שייבנה סביב הפלטפורמה הנגררת.
            </p>
          </article>
        </div>
      </section>

      <section className="section-shell">
        <div className="container section-stack">
          <h2>AI ככלי הנדסי, לא כפתור קסם לייצור חוקי</h2>
          <p className="section-intro">
            ה-PDF האחרון מחדד נקודה חשובה: אין היום AI שמוציא לבד blueprint מאושר רגולטורית לוואן או אוטובוס
            ומייתר מהנדסים, בדיקות, ו-homologation. כן אפשר להשתמש ב-AI כדי להאיץ משמעותית את תהליך
            ההנדסה, ה-CAD, וה-compliance review.
          </p>
          <div className="feature-grid">
            {cadStackRows.map((item) => (
              <article key={item.title}>
                <h3>{item.title}</h3>
                <p>{item.text}</p>
              </article>
            ))}
          </div>
          <article className="notice-card">
            <h3>קו אדום מוצרי</h3>
            <p>
              Atlas לא אמור להציג AI כמי ש&quot;מאשר רגולציה&quot; או מחליף מהנדס רכב/גוף מאשר. התפקיד הנכון של
              המערכת הוא להפיק חלופות תכנון, לייצר מסמכי עבודה מהר יותר, ולסמן סיכוני compliance מוקדם.
            </p>
          </article>
          <article className="notice-card">
            <h3>מה רגולטורים באמת בודקים</h3>
            <p>
              לא קיימת קטגוריה אמיתית של &quot;CAD מאושר רגולטורית&quot;. מה שנבדק בעולם האמיתי הוא traceability,
              validation, simulation evidence, איכות תיעוד, ואחריות הנדסית שאפשר להגן עליה מול Israel MoT,
              UNECE, וגורמי homologation רלוונטיים.
            </p>
          </article>
          <article className="notice-card">
            <h3>אין payload קסם לרכב שלם</h3>
            <p>
              גם עם Onshape, מערכת אמיתית לא שולחת בקשה אחת של &quot;תכנן לי רכב יוקרה&quot; ומקבלת blueprint מלא.
              היא מריצה orchestration של הרבה צעדים קטנים: sketch, extrude, loft, assembly, export, mass properties,
              ו-validation לכל רכיב או תת-מערכת בנפרד.
            </p>
          </article>
          <article className="notice-card">
            <h3>לצפייה רצינית צריך native app, לא עוד טאבה בדפדפן</h3>
            <p>
              אם Atlas רוצה exploded views אינטראקטיביים, cinematic timelines, ותגובות בזמן אמת על scene מושהה,
              הכיוון הנכון הוא macOS native על Apple Silicon עם שכבת תצוגה ייעודית לקבצי assembly היררכיים,
              לא עוד WebGPU viewer שמנסה להיות תחנת הנדסה מלאה.
            </p>
          </article>
          <article className="notice-card">
            <h3>שכבת הביצוע הנכונה ל-R&amp;D חסכוני</h3>
            <p>
              אם Atlas בוחר ב-FreeCAD ו-Blender, ה-AI צריך לכתוב Python שנרץ בתוך sandbox מבודד, לייצר
              קבצי STEP/STL/OBJ/PNG לתיקיית יצוא מאובטחת, ורק אז להעביר תוצרים לבדיקה אנושית ולהמשך תהליך.
            </p>
          </article>
        </div>
      </section>

      <section className="section-shell">
        <div className="container section-stack">
          <h2>החבילות שלנו</h2>
          <p className="section-intro">שתי דרכים להתחיל: לטעום את הקונספט או להפוך חופש להרגל קבוע.</p>
          <div className="cards-grid">
            <ProductCard
              badge="מסלול ניסיון"
              title="מסע חווייתי"
              description="חבילה קצרה למי שרוצה לבדוק אם בית נייד באמת משנה את חוויית הטיול." 
              bullets={[
                "מתאים לזוגות/חברים/צעירים אחרי צבא",
                "תכנון יום-יום מותאם לקצב שלכם",
                "תדריך נהיגה ותפעול ברור"
              ]}
            />
            <ProductCard
              badge="חופש מתמשך"
              title="מנוי מסע"
              description="גישה חוזרת ומסודרת לחופשות ניידות לאורך השנה, עם עדיפות בזמינות וליווי." 
              bullets={[
                "משתלם למי שיוצא לעיתים קרובות",
                "עדיפות בקביעת מועדים",
                "תמיכה תפעולית ותכנון מסלול שוטף"
              ]}
            />
          </div>
        </div>
      </section>

      <section className="section-shell accent-shell">
        <div className="container section-stack">
          <h2>עזרה בתכנון טיול - כלולה בחינם</h2>
          <p className="section-intro">
            זה ההבדל שלנו. לפני כל יציאה בונים יחד תכנית עם לוגיסטיקה אמיתית לישראל, בלי הבטחות לא
            חוקיות ובלי הפתעות בדרך.
          </p>
          <div className="feature-grid">
            <article>
              <h3>מים ומים אפורים</h3>
              <p>מיפוי מראש של מילוי וריקון חוקי בלבד, עם חלופות לכל אזור.</p>
            </article>
            <article>
              <h3>לינת לילה</h3>
              <p>הכוונה ללינה מוסדרת + תכנית גיבוי אם המקום הראשון מלא.</p>
            </article>
            <article>
              <h3>מקלחות ושגרה</h3>
              <p>שילוב חניונים, מתחמי רחצה, או חדרי כושר לפי המסלול והתקציב.</p>
            </article>
          </div>
        </div>
      </section>

      <section className="section-shell">
        <div className="container section-stack">
          <h2>איך זה עובד בעולם האמיתי</h2>
          <p className="section-intro">
            המטרה היא לא רק רעיון יפה, אלא חוויה עקבית בשטח: תדריך ברור, צ&apos;ק-ליסט מסודר, ותכנית גיבוי
            לפני שיוצאים.
          </p>
          <div className="feature-grid">
            <article>
              <h3>יציאה מסודרת</h3>
              <p>לפני כל מסע מקבלים הסבר תפעולי, כללי נהיגה, ויישור קו על לינה, מים ומקלחות.</p>
            </article>
            <article>
              <h3>חוקיות לפני אילתור</h3>
              <p>המלצות הלינה והתפעול נשארות בגבולות מה שאפשרי ומכבד את השטח, בלי פתרונות מפוקפקים.</p>
            </article>
            <article>
              <h3>קשר מהיר אם משהו משתנה</h3>
              <p>אם מסלול נתקע, יש ערוץ WhatsApp ישיר כדי לעדכן תכנית ולא לאבד את החופש שבשבילו יצאתם.</p>
            </article>
          </div>
        </div>
      </section>

      <section className="section-shell accent-shell">
        <div className="container section-stack">
          <h2>מה עוד חייב להיסגר כדי שזה יהיה מוכן למשתמש אמיתי</h2>
          <p className="section-intro">
            כדי להפוך קונספט של cargo trailer platform למוצר אמיתי, יש כמה שכבות שצריכות להיות סגורות
            ברמת engineering, חוקיות, ותפעול לקוח.
          </p>
          <article className="notice-card">
            <ul>
              {readinessRows.map((row) => (
                <li key={row}>{row}</li>
              ))}
            </ul>
          </article>
        </div>
      </section>

      <section className="section-shell">
        <div className="container section-stack">
          <div className="row-between">
            <h2>מדריכים בישראל</h2>
            <Link href="/guides" className="link-arrow">
              לכל המדריכים
            </Link>
          </div>

          <div className="cards-grid">
            {guides.map((guide) => (
              <GuideCard key={guide.slug} guide={guide} />
            ))}
          </div>
        </div>
      </section>

      <section className="section-shell">
        <div className="container section-stack teaser-box">
          <h2>יש שאלות לפני שסוגרים?</h2>
          <p>
            ענינו על נהיגה, מקלחות, עלויות מול מלונות, בטיחות, ואיך לא נתקעים עם מים אפורים באמצע הדרך.
          </p>
          <div className="hero-actions">
            <Link href="/faq" className="btn btn-secondary">
              מעבר ל-FAQ
            </Link>
            <WhatsAppButton text="שיחה מהירה ב-WhatsApp" className="btn-ghost" />
          </div>
        </div>
      </section>
    </>
  );
}
