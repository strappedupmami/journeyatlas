import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { WhatsAppButton } from "@/components/WhatsAppButton";
import { getAllGuides, getGuideBySlug } from "@/lib/guides";
import { markdownToHtml } from "@/lib/markdown";

type GuidePageProps = {
  params: {
    slug: string;
  };
};

export function generateStaticParams() {
  return getAllGuides().map((guide) => ({ slug: guide.slug }));
}

export function generateMetadata({ params }: GuidePageProps): Metadata {
  const guide = getGuideBySlug(params.slug);

  if (!guide) {
    return {
      title: "מדריך לא נמצא | אטלס מסע"
    };
  }

  return {
    title: `${guide.title} | אטלס מסע`,
    description: guide.summary
  };
}

export default function GuidePage({ params }: GuidePageProps) {
  const guide = getGuideBySlug(params.slug);

  if (!guide) {
    notFound();
  }

  const html = markdownToHtml(guide.body);

  return (
    <section className="page-shell">
      <div className="container section-stack">
        <p className="kicker">מדריך מסלול</p>
        <h1>{guide.title}</h1>
        <p className="section-intro">{guide.summary}</p>

        <div className="guide-meta-grid" aria-label="פרטי מדריך">
          <article>
            <h2>למי מתאים</h2>
            <p>{guide.audience}</p>
          </article>
          <article>
            <h2>רמת נהיגה</h2>
            <p>{guide.drivingLevel}</p>
          </article>
          <article>
            <h2>משך מסלול</h2>
            <p>{guide.days}</p>
          </article>
          <article>
            <h2>לינה</h2>
            <p>{guide.sleepPlan}</p>
          </article>
          <article>
            <h2>מים/מים אפורים</h2>
            <p>{guide.waterPlan}</p>
          </article>
          <article>
            <h2>מקלחות</h2>
            <p>{guide.showerPlan}</p>
          </article>
        </div>

        <article className="markdown-article" dangerouslySetInnerHTML={{ __html: html }} />

        <article className="notice-card">
          <h2>לא להיתקע בדרך</h2>
          <p>{guide.dontGetStuck}</p>
          <p>תכנון טיול מלא כלול בחינם בכל הזמנה של אטלס מסע.</p>
          <WhatsAppButton text="לתיאום מסלול חינם ב-WhatsApp" />
        </article>
      </div>
    </section>
  );
}
