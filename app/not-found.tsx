import Link from "next/link";

export default function NotFoundPage() {
  return (
    <section className="page-shell">
      <div className="container section-stack">
        <h1>העמוד לא נמצא</h1>
        <p>יכול להיות שהקישור השתנה או שהמדריך עדיין לא פורסם.</p>
        <Link href="/guides" className="btn btn-secondary">
          חזרה למדריכים
        </Link>
      </div>
    </section>
  );
}
