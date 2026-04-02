import type { MetadataRoute } from "next";
import { getAllGuides } from "@/lib/guides";
import { SITE_INDEXABLE, SITE_URL } from "@/lib/site";

const staticRoutes = [
  "",
  "/packages",
  "/guides",
  "/faq",
  "/policies",
  "/contact",
  "/blackhaven",
  "/blackhaven/readiness",
  "/blackhaven/downloads"
];

export default function sitemap(): MetadataRoute.Sitemap {
  if (!SITE_INDEXABLE) {
    return [];
  }

  const now = new Date();
  const guideRoutes = getAllGuides().map((guide) => ({
    url: `${SITE_URL}/guides/${guide.slug}`,
    lastModified: now,
    changeFrequency: "weekly" as const,
    priority: 0.7
  }));

  return [
    ...staticRoutes.map((route, index) => ({
      url: `${SITE_URL}${route}`,
      lastModified: now,
      changeFrequency: route === "" ? ("weekly" as const) : ("monthly" as const),
      priority: index === 0 ? 1 : 0.8
    })),
    ...guideRoutes
  ];
}
