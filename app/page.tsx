import Link from "next/link";
import { GuideCard } from "@/components/GuideCard";
import { ProductCard } from "@/components/ProductCard";
import { WhatsAppButton } from "@/components/WhatsAppButton";
import { getAllGuides } from "@/lib/guides";
import { BRAND_SUBTITLE, BRAND_TAGLINE } from "@/lib/site";

export default function HomePage() {
  const guides = getAllGuides().slice(0, 3);

  return (
    <>
      <section className="hero-section">
        <div className="container hero-grid">
          <div>
            <p className="kicker">אטלס מסע</p>
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
