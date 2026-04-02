export const BRAND_NAME = "אטלס";
export const BRAND_TAGLINE = "חופשה בלי מלונות";
export const BRAND_SUBTITLE = "המלון שלך על גלגלים";
export const SITE_NAME = "Atlas/אטלס";

export const NAV_LINKS = [
  { href: "/", label: "דף הבית" },
  { href: "/packages", label: "חבילות ומחירים" },
  { href: "/guides", label: "מדריכים בישראל" },
  { href: "/faq", label: "שאלות נפוצות" },
  { href: "/policies", label: "מדיניות" },
  { href: "/contact", label: "צור קשר" }
] as const;

export const CONTACT_WHATSAPP_MESSAGE =
  "היי אטלס, אשמח לקבל פרטים על מסע חווייתי/מנוי מסע + עזרה בתכנון טיול";

export const SITE_DESCRIPTION =
  "אטלס - חופשה בלי מלונות. בית נייד עם עזרה חינמית בתכנון טיול ולוגיסטיקה בישראל.";

export const SITE_INDEXABLE = process.env.NEXT_PUBLIC_SITE_INDEXABLE === "true";
export const SITE_URL = (process.env.NEXT_PUBLIC_SITE_URL ?? "https://atlasmasa.com").replace(/\/+$/, "");
export const SUPPORT_EMAIL = process.env.NEXT_PUBLIC_SUPPORT_EMAIL ?? "hello@atlasmasa.com";
export const WHATSAPP_NUMBER = process.env.NEXT_PUBLIC_WHATSAPP_NUMBER ?? "972500000000";
export const WHATSAPP_NUMBER_DISPLAY = process.env.NEXT_PUBLIC_WHATSAPP_DISPLAY ?? "+972 50-000-0000";

export function getMetadataBase(): URL {
  try {
    return new URL(SITE_URL);
  } catch {
    return new URL("https://atlasmasa.com");
  }
}
