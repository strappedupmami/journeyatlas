const faqItems = [
  {
    question: "זה קשה לנהוג על בית נייד?",
    answer:
      "לרוב הנהגים זה מסתדר מהר מאוד. לפני יציאה מקבלים תדריך קצר עם דגשים לחניה, סיבובים ותכנון דרך."
  },
  {
    question: "מה עושים עם מקלחות בדרך?",
    answer:
      "מתכננים מראש: חניונים מוסדרים, נקודות רחצה מוכרות, או פתרון חדר כושר לפי המסלול והתקציב."
  },
  {
    question: "איפה ישנים בלילה?",
    answer:
      "מכוונים ללינה חוקית ומסודרת בלבד. בכל מסלול יש גם חלופת גיבוי אם מקום לינה מתמלא."
  },
  {
    question: "מה לגבי מים ומים אפורים?",
    answer:
      "זה נושא קריטי בישראל. לכן אנחנו בונים תכנית מילוי וריקון חוקית מראש ולא ממליצים על שום פתרון לא חוקי."
  },
  {
    question: "כמה זה משתלם מול מלונות?",
    answer:
      "זה תלוי עונה וקצב טיול, אבל הערך הגדול הוא חופש תנועה, פרטיות, וחיסכון בזמן מעבר בין מלונות."
  },
  {
    question: "האם יש כלל עישון?",
    answer: "כן. ללא עישון בכלל בתוך הרכב, כדי לשמור על איכות, ניקיון וריח נעימים לכל לקוח הבא."
  }
];

export default function FaqPage() {
  return (
    <section className="page-shell">
      <div className="container section-stack">
        <p className="kicker">שאלות נפוצות</p>
        <h1>כל מה שחשוב לדעת לפני שיוצאים</h1>
        <div className="faq-list">
          {faqItems.map((item) => (
            <article key={item.question} className="faq-item">
              <h2>{item.question}</h2>
              <p>{item.answer}</p>
            </article>
          ))}
        </div>
      </div>
    </section>
  );
}
