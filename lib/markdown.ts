function escapeHtml(text: string): string {
  return text
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function decodeBasicEntities(text: string): string {
  return text
    .replaceAll("&amp;", "&")
    .replaceAll("&quot;", '"')
    .replaceAll("&#39;", "'")
    .replaceAll("&lt;", "<")
    .replaceAll("&gt;", ">");
}

function sanitizeHref(rawHref: string): string | null {
  const href = decodeBasicEntities(rawHref).trim();
  if (!href) return null;

  if (href.startsWith("/") || href.startsWith("#")) {
    return href;
  }

  try {
    const parsed = new URL(href);
    const protocol = parsed.protocol.toLowerCase();
    if (protocol === "https:" || protocol === "mailto:" || protocol === "tel:") {
      return parsed.toString();
    }
  } catch {
    return null;
  }

  return null;
}

function inlineMarkdown(text: string): string {
  const escaped = escapeHtml(text);
  return escaped
    .replace(/\*\*(.+?)\*\*/g, "<strong>$1</strong>")
    .replace(/\[(.+?)\]\((.+?)\)/g, (_match, label, href) => {
      const safeHref = sanitizeHref(String(href));
      if (!safeHref) {
        return String(label);
      }
      return `<a href="${escapeHtml(safeHref)}" target="_blank" rel="noopener noreferrer">${String(label)}</a>`;
    });
}

export function markdownToHtml(markdown: string): string {
  const lines = markdown.split(/\r?\n/);
  const html: string[] = [];
  let listBuffer: string[] = [];

  const flushList = () => {
    if (listBuffer.length > 0) {
      html.push(`<ul>${listBuffer.join("")}</ul>`);
      listBuffer = [];
    }
  };

  for (const line of lines) {
    const trimmed = line.trim();

    if (!trimmed) {
      flushList();
      continue;
    }

    if (trimmed.startsWith("- ")) {
      listBuffer.push(`<li>${inlineMarkdown(trimmed.slice(2))}</li>`);
      continue;
    }

    flushList();

    if (trimmed.startsWith("### ")) {
      html.push(`<h3>${inlineMarkdown(trimmed.slice(4))}</h3>`);
      continue;
    }

    if (trimmed.startsWith("## ")) {
      html.push(`<h2>${inlineMarkdown(trimmed.slice(3))}</h2>`);
      continue;
    }

    if (trimmed.startsWith("# ")) {
      html.push(`<h1>${inlineMarkdown(trimmed.slice(2))}</h1>`);
      continue;
    }

    html.push(`<p>${inlineMarkdown(trimmed)}</p>`);
  }

  flushList();
  return html.join("\n");
}
