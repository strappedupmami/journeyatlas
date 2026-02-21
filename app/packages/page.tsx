import { WhatsAppButton } from "@/components/WhatsAppButton";

const packageRows = [
  {
    name: "מסע חווייתי",
    fit: "למי שרוצה להתנסות בפעם הראשונה",
    includes: [
      "חופשה קצרה 2-4 לילות",
      "הדרכת הפעלה מלאה לפני יציאה",
      "תכנון טיול חינם (מסלול + לינה + מים/אפור)",
      "תמיכה בהודעות בזמן המסע"
    ]
  },
  {
    name: "מנוי מסע",
    fit: "למשפחות/זוגות שרוצים לצאת כמה פעמים בשנה",
    includes: [
      "חבילת ימי שימוש שנתית",
      "עדיפות בבחירת מועדים",
      "ליווי תכנון מתמשך ללא עלות נוספת",
      "שדרוגים והטבות מנוי לפי זמינות"
    ]
  }
];

export default function PackagesPage() {
  return (
    <section className="page-shell">
      <div className="container section-stack">
        <p className="kicker">חבילות ומחירים</p>
        <h1>תמחור ברור. ערך אמיתי. בלי הפתעות.</h1>
        <p className="section-intro">
          המספרים הסופיים ייסגרו לפני ההשקה הרשמית, אבל המבנה כבר ברור: מסע חווייתי לניסיון מהיר,
          ומנוי מסע לחופש חוזר ומשתלם.
        </p>

        <div className="pricing-grid">
          {packageRows.map((row) => (
            <article key={row.name} className="pricing-card">
              <h2>{row.name}</h2>
              <p className="pricing-fit">{row.fit}</p>
              <ul>
                {row.includes.map((item) => (
                  <li key={item}>{item}</li>
                ))}
              </ul>
            </article>
          ))}
        </div>

        <article className="notice-card">
          <h2>איך &quot;תכנון טיול חינם&quot; עובד בפועל?</h2>
          <ol>
            <li>ממלאים איתנו שיחת אפיון קצרה: זמן, קהל, סגנון ותקציב.</li>
            <li>מקבלים תכנית בסיס: נהיגה, לינה, מים, מקלחות, תחנות גיבוי.</li>
            <li>יוצאים למסע עם ביטחון תפעולי, בלי לשלם על השירות הזה בנפרד.</li>
          </ol>
        </article>

        <div>
          <WhatsAppButton text="לקבלת מחירון עדכני ב-WhatsApp" />
        </div>
      </div>
    </section>
  );
}
