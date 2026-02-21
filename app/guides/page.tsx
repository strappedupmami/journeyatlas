import { GuideCard } from "@/components/GuideCard";
import { WhatsAppButton } from "@/components/WhatsAppButton";
import { getAllGuides } from "@/lib/guides";

export default function GuidesHubPage() {
  const guides = getAllGuides();

  return (
    <section className="page-shell">
      <div className="container section-stack">
        <p className="kicker">מדריכים בישראל</p>
        <h1>תוכן שימושי שאפשר ליישם בשטח</h1>
        <p className="section-intro">
          כל מדריך בנוי לסקירה מהירה + תפעול אמיתי: מסלול, סוגי לינה, תכנית מים/מים אפורים, מקלחות וטיפים
          שמונעים תקיעות.
        </p>

        <div className="cards-grid">
          {guides.map((guide) => (
            <GuideCard key={guide.slug} guide={guide} />
          ))}
        </div>

        <article className="notice-card">
          <h2>רוצים מסלול מותאם אישית?</h2>
          <p>בכל הזמנה של אטלס, תכנון הטיול כלול בחינם.</p>
          <WhatsAppButton text="לקבלת תכנון חינם ב-WhatsApp" />
        </article>
      </div>
    </section>
  );
}
