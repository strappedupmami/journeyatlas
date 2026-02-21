# אטלס (Atlas/אטלס)

Hebrew-first RTL website built with Next.js + TypeScript.

## Phase 1 scope
- Homepage with product positioning and WhatsApp CTA
- Foundational pages: Packages, Guides hub, FAQ, Policies, Contact
- Markdown-based guide engine with dynamic guide pages
- Staging mode defaults to `noindex`

## Stack
- Next.js (App Router)
- TypeScript
- Markdown files for guides (no CMS yet)

## Quick start (local)
1. Install dependencies:
   ```bash
   npm install
   ```
2. Copy environment file:
   ```bash
   cp .env.example .env.local
   ```
3. Start dev server:
   ```bash
   npm run dev
   ```
4. Open:
   ```text
   http://localhost:3000
   ```

## Quality checks
```bash
npm run lint
npm run typecheck
npm run build
```

## Staging indexing policy
- Default is `NEXT_PUBLIC_SITE_INDEXABLE=false`
- `app/robots.ts` disallows crawling when indexable is false
- `app/layout.tsx` metadata also sets `noindex, nofollow` when false

## How to add a new guide
1. Copy template:
   ```bash
   cp content/guides/TEMPLATE.md content/guides/<new-slug>.md
   ```
2. Fill the frontmatter + sections in Hebrew.
3. Save. The guide appears automatically in `/guides` and gets a route at `/guides/<new-slug>`.

## GitHub setup (first push)
Run from project root:

```bash
git init
git add .
git commit -m "Initial Atlas/אטלס RTL Next.js staging site"
git branch -M main
git remote add origin https://github.com/<YOUR_USER>/<YOUR_REPO>.git
git push -u origin main
```

## Daily branch workflow (Yasha-friendly)
```bash
git checkout -b feature/<short-name>
# make small change
git add <files>
git commit -m "Short clear message"
git push -u origin feature/<short-name>
```
Then either open PR, or merge manually if working solo.

## Vercel preview deploy
1. Import the GitHub repository into Vercel.
2. In project settings, set env vars for Preview:
   - `NEXT_PUBLIC_SITE_INDEXABLE=false`
   - `NEXT_PUBLIC_WHATSAPP_NUMBER=<number>`
3. Every push to `main` (or preview branch) generates a preview URL.
4. Keep staging non-indexed until launch.

## Launch switch later
When ready for public launch:
- set `NEXT_PUBLIC_SITE_INDEXABLE=true`
- add real domain + canonical strategy
- add sitemap generation
