import Link from "next/link";
import { BRAND_NAME } from "@/lib/site";

export function SiteFooter() {
  const currentYear = new Date().getFullYear();

  return (
    <footer className="site-footer">
      <div className="container footer-grid">
        <div>
          <h2 className="footer-brand">{BRAND_NAME}</h2>
          <p className="footer-text">בית נייד, חופש תנועה, ותכנון טיול חינם כחלק מהחבילה.</p>
        </div>

        <div>
          <h3 className="footer-heading">עמודים</h3>
          <ul className="footer-links">
            <li>
              <Link href="/packages">חבילות ומחירים</Link>
            </li>
            <li>
              <Link href="/guides">מדריכים בישראל</Link>
            </li>
            <li>
              <Link href="/faq">שאלות נפוצות</Link>
            </li>
            <li>
              <Link href="/policies">מדיניות</Link>
            </li>
          </ul>
        </div>

        <div>
          <h3 className="footer-heading">זמינות</h3>
          <p className="footer-text">סטטוס נוכחי: סביבת תצוגה מקדימה (Staging)</p>
          <p className="footer-text">{currentYear} © {BRAND_NAME}</p>
        </div>
      </div>
    </footer>
  );
}
