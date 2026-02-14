import { WhatsAppButton } from "@/components/WhatsAppButton";

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
          </ul>
          <WhatsAppButton text="פתיחת שיחה ב-WhatsApp" />
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
