import Link from "next/link";
import { BRAND_NAME, NAV_LINKS } from "@/lib/site";

export function SiteHeader() {
  return (
    <header className="site-header">
      <div className="container header-inner">
        <Link href="/" className="brand-link" aria-label="אטלס - עמוד הבית">
          <span className="brand-title">{BRAND_NAME}</span>
          <span className="brand-badge">RTL</span>
        </Link>

        <nav aria-label="ניווט ראשי">
          <ul className="nav-list">
            {NAV_LINKS.map((link) => (
              <li key={link.href}>
                <Link href={link.href} className="nav-link">
                  {link.label}
                </Link>
              </li>
            ))}
          </ul>
        </nav>
      </div>
    </header>
  );
}
