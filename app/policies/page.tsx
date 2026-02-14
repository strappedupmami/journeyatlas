const policySections = [
  {
    title: "ללא עישון",
    points: [
      "העישון אסור בתוך הרכב בכל מצב.",
      "שמירה על ריח וניקיון היא חלק מרכזי מהאיכות של אטלס מסע.",
      "הפרת הכלל יכולה לגרור חיוב ניקוי מיוחד לפי המדיניות."
    ]
  },
  {
    title: "מים, מים אפורים וחוקיות",
    points: [
      "מילוי מים וריקון מים אפורים מתבצעים רק בנקודות חוקיות ומוסדרות.",
      "לא מבצעים ריקון בשטח פתוח, בחופים, או בכל מקום שאינו מיועד לכך.",
      "אנחנו מספקים תכנית תפעול מראש כדי למנוע טעויות בדרך."
    ]
  },
  {
    title: "אחריות שימוש וניקיון",
    points: [
      "החזרת הרכב מתבצעת לפי צ'ק-ליסט סיום שנמסר לפני היציאה.",
      "יש לשמור על ציוד הרכב ועל סביבת נהיגה בטוחה ואחראית.",
      "כל שימוש חריג ידווח מראש כדי שנוכל לסייע בזמן אמת."
    ]
  }
];

export default function PoliciesPage() {
  return (
    <section className="page-shell">
      <div className="container section-stack">
        <p className="kicker">כללים ומדיניות</p>
        <h1>חוויית פרימיום דורשת סטנדרט ברור</h1>
        <p className="section-intro">
          המדיניות נועדה לשמור על בטיחות, ניקיון, וחוויה עקבית לכל מי שיוצא למסע עם אטלס מסע.
        </p>

        <div className="policy-grid">
          {policySections.map((section) => (
            <article key={section.title} className="policy-card">
              <h2>{section.title}</h2>
              <ul>
                {section.points.map((point) => (
                  <li key={point}>{point}</li>
                ))}
              </ul>
            </article>
          ))}
        </div>
      </div>
    </section>
  );
}
