import Link from "next/link";
import type { Guide } from "@/lib/guides";

export function GuideCard({ guide }: { guide: Guide }) {
  return (
    <article className="guide-card">
      <h3>{guide.title}</h3>
      <p>{guide.summary}</p>
      <dl>
        <div>
          <dt>קהל יעד</dt>
          <dd>{guide.audience}</dd>
        </div>
        <div>
          <dt>רמת נהיגה</dt>
          <dd>{guide.drivingLevel}</dd>
        </div>
        <div>
          <dt>משך</dt>
          <dd>{guide.days}</dd>
        </div>
      </dl>
      <Link href={`/guides/${guide.slug}`} className="link-arrow">
        למדריך המלא
      </Link>
    </article>
  );
}
