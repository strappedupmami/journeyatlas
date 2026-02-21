# Day 1 Playbook (Yasha-Friendly)
Date target: Monday, February 16, 2026

## Objective
Ship a working Hebrew RTL preview build without public launch.

## Rules
- Yasha runs commands and copies outputs.
- Codex/GPT writes code and decides implementation details.
- Keep commits small and frequent.
- Do not launch production domain yet.

## Step 1 - Open project
```bash
cd /Users/avrohom/Downloads/journeyatlas
```

## Step 2 - Run local website
```bash
npm install
cp .env.example .env.local
npm run dev
```
Open: `http://localhost:3000`

## Step 3 - Confirm RTL + Hebrew baseline
Checklist:
- `dir="rtl"` in layout
- Hebrew nav labels
- WhatsApp CTA visible on Home/Pricing/Contact

## Step 4 - Guides system check
Verify:
- `/guides` lists guides
- Each guide has: summary, fit, driving level, water/grey plan, shower options, CTA

## Step 5 - Safety + policy check
Verify copy includes:
- No smoking is strict
- No illegal dumping guidance
- Travel help included free

## Step 6 - Commit and push
```bash
git add .
git commit -m "Day 1 Hebrew RTL + guides + CTA polish"
# set your remote once:
# git remote add origin https://github.com/<user>/<repo>.git
git push -u origin main
```

## Step 7 - Preview deploy only
- Connect repo to Vercel.
- Keep staging `noindex`.
- Share preview URL for review.

## Step 8 - Stop point
Stop after preview works. Do not add booking engine yet.

## Optional: Run Rust Concierge + connect from static homepage
1. Start concierge API:
```bash
cd /Users/avrohom/Downloads/journeyatlas/atlas-concierge
cargo run -p atlas-api
```
2. Open static website:
- `/Users/avrohom/Downloads/journeyatlas/website/homepage.html`
3. Click `AI קונסיירז׳` in nav (or open `website/concierge-local.html`).
4. In the page keep:
- API base: `http://localhost:8080`
- API key: `dev-atlas-key` (unless changed in env)
5. Test:
- Health
- Chat
- Plan Trip

## Optional evening task
Record outline for founder story (not full shoot):
1. Why Atlas/אטלס exists
2. What problem "חופש בלי מלונות" solves
3. Why no-smoking and legal water/grey rules matter
