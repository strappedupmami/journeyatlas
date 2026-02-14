import fs from "node:fs";
import path from "node:path";

const guidesDirectory = path.join(process.cwd(), "content", "guides");

export type Guide = {
  slug: string;
  title: string;
  summary: string;
  audience: string;
  drivingLevel: string;
  days: string;
  sleepPlan: string;
  waterPlan: string;
  showerPlan: string;
  dontGetStuck: string;
  body: string;
};

function parseFrontmatter(markdown: string): { frontmatter: Record<string, string>; body: string } {
  const match = markdown.match(/^---\n([\s\S]*?)\n---\n?([\s\S]*)$/);

  if (!match) {
    return { frontmatter: {}, body: markdown };
  }

  const [, rawFrontmatter, body] = match;
  const frontmatter: Record<string, string> = {};

  for (const line of rawFrontmatter.split(/\r?\n/)) {
    if (!line.trim() || line.trim().startsWith("#")) {
      continue;
    }

    const separatorIndex = line.indexOf(":");
    if (separatorIndex === -1) {
      continue;
    }

    const key = line.slice(0, separatorIndex).trim();
    const value = line.slice(separatorIndex + 1).trim().replace(/^"|"$/g, "");

    if (key) {
      frontmatter[key] = value;
    }
  }

  return { frontmatter, body };
}

function toGuide(slug: string, markdown: string): Guide {
  const { frontmatter, body } = parseFrontmatter(markdown);

  return {
    slug,
    title: frontmatter.title ?? slug,
    summary: frontmatter.summary ?? "",
    audience: frontmatter.audience ?? "לזוגות, חברים ומשפחות צעירות",
    drivingLevel: frontmatter.drivingLevel ?? "קל-בינוני",
    days: frontmatter.days ?? "2-3 ימים",
    sleepPlan: frontmatter.sleepPlan ?? "לינה מוסדרת",
    waterPlan: frontmatter.waterPlan ?? "תכנון נקודות מילוי/ריקון מראש",
    showerPlan: frontmatter.showerPlan ?? "חניונים מוסדרים וחדרי כושר",
    dontGetStuck: frontmatter.dontGetStuck ?? "תמיד להחזיק תכנית גיבוי",
    body: body.trim()
  };
}

export function getGuideSlugs(): string[] {
  if (!fs.existsSync(guidesDirectory)) {
    return [];
  }

  return fs
    .readdirSync(guidesDirectory)
    .filter((fileName) => fileName.endsWith(".md") && fileName !== "TEMPLATE.md")
    .map((fileName) => fileName.replace(/\.md$/, ""));
}

export function getGuideBySlug(slug: string): Guide | null {
  const fullPath = path.join(guidesDirectory, `${slug}.md`);

  if (!fs.existsSync(fullPath)) {
    return null;
  }

  const markdown = fs.readFileSync(fullPath, "utf8");
  return toGuide(slug, markdown);
}

export function getAllGuides(): Guide[] {
  return getGuideSlugs()
    .map((slug) => getGuideBySlug(slug))
    .filter((guide): guide is Guide => Boolean(guide))
    .sort((a, b) => a.title.localeCompare(b.title, "he"));
}
