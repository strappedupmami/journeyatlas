import { WhatsAppButton } from "@/components/WhatsAppButton";
import { SUPPORT_EMAIL, WHATSAPP_NUMBER_DISPLAY } from "@/lib/site";

export default function ContactPage() {
  return (
    <section className="page-shell">
      <div className="container section-stack">
        <p className="kicker">צור קשר / זמינות</p>
        <h1>מתאמים מסע בקליק</h1>
        <p className="section-intro">
          ערוץ הקשר הראשי הוא WhatsApp כדי שנוכל לתת תשובה מהירה, לבדוק זמינות, ולהתחיל תכנון מסלול.
        </p>

        <article className="contact-panel">
          <h2>מה כדאי לשלוח בהודעה ראשונה?</h2>
          <ul>
            <li>תאריכים משוערים</li>
            <li>כמה אנשים יוצאים</li>
            <li>סגנון טיול מועדף (ים/מדבר/צפון/מעורב)</li>
            <li>האם אתם בודקים מסע חווייתי או מנוי מסע</li>
            <li>אם יש רכב גרירה קיים: דגם, כושר גרירה, וניסיון בגרירה</li>
          </ul>
          <WhatsAppButton text="פתיחת שיחה ב-WhatsApp" />
        </article>

        <article className="notice-card">
          <h2>פרטי קשר ותיאום</h2>
          <ul>
            <li>WhatsApp: {WHATSAPP_NUMBER_DISPLAY}</li>
            <li>אימייל: {SUPPORT_EMAIL}</li>
            <li>מומלץ להשאיר חלון תאריכים ולא רק יום בודד, כדי לאפשר תכנון ריאלי.</li>
          </ul>
        </article>

        <article className="notice-card">
          <h2>מה חייב להיות ברור לפני השקה לצרכן אמיתי</h2>
          <ul>
            <li>לאיזה רכבי גרירה כל דגם מתאים בפועל</li>
            <li>מהו משקל אמת בכל מצב שימוש, לא רק ב-spec sheet</li>
            <li>איך נראים power, מים, קירור, אוורור ו-SOPs בזמן תקלה</li>
            <li>מה כבר זמין היום ומה עדיין ב-roadmap של Atlas Vehicle OS</li>
          </ul>
        </article>

        <article className="notice-card">
          <h2>סטטוס אתר</h2>
          <p>
            האתר כרגע ב-Staging לצורכי בנייה ובדיקות. התוכן מתעדכן באופן שוטף לפני השקה ציבורית.
          </p>
        </article>
      </div>
    </section>
  );
}
