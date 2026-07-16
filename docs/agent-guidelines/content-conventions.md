# Content Conventions

How copy/content should read across Sil's products, and what pages every public-facing
website/product must ship with. Pairs with `design-conventions.md` — the writing should match
the restrained, considered visual register: no hype language for a calm interface.

## Mandatory pages (every public website/product ships these)

Every project with a public-facing website — marketing site, SaaS product, app landing page —
must include, from the start, not as an afterthought:

- **Support** — a page (or clear contact path: email, form, help-center link) for how a user
  gets help. Don't ship a product without a visible way to reach support.
- **Terms and Conditions** — even a short, plain-language version for an early-stage/small
  product; expand it as the product and its legal exposure grow.
- **Privacy Policy** — state what data is collected, why, and how it's handled/stored,
  matching reality (don't template in claims about data handling that aren't true for this
  project). Cloudflare/D1/analytics providers actually in use should be named if the policy
  gets specific.

Treat these three as required scaffolding for a new project's site, alongside the actual
product pages — set up placeholder/stub versions early rather than leaving them for "later."
Link them from the footer, consistently, on every page.

## Voice and tone

- Calm, direct, matter-of-fact — never hype. Avoid "revolutionary," "game-changing,"
  "seamless," "cutting-edge," "AI-powered magic," exclamation points as a crutch. This mirrors
  the same restraint as the visual design: the product should not need to shout about itself.
- Avoid vague, unverifiable claims (see `status/AGENTS.md`'s explicit "avoid hype language...
  vague AI features... magical claims" rule) — say specifically what the thing does.
- Short sentences, plain words. Prefer a concrete verb over an abstract noun
  ("delete the file" over "facilitate file removal").
- Second person, active voice: talk to "you," not "the user."
- Headlines/labels describe what something *is* or *does*, not a marketing tagline for its
  own sake — clarity over cleverness in UI copy specifically (button labels, empty states,
  error messages). Marketing/landing copy can have more personality than in-app UI copy, but
  should still stay out of hype territory.

## Structure & hierarchy

- Lead with the point. Don't bury the useful sentence under three sentences of throat-clearing.
- Use real headings to create scannable structure rather than long undifferentiated paragraphs
  — this is true for docs, marketing pages, and in-app help content alike.
- Uppercase micro-labels (eyebrows, section labels) are fine and match the visual system
  (see `design-conventions.md`) — but keep them short (1–3 words), not full sentences in caps.
- Empty states, error messages, and confirmation copy should say exactly what happened and
  what to do next — not a generic "Something went wrong" without a next step, and not an
  apologetic tone piled on top of the actual information.

## Localization

Where a project supports multiple locales (seen as `en.json`/`nl.json` pairs in several repos):
never hardcode user-facing strings in components — all copy lives in locale files, and every
locale file gets updated together when a string changes, not just the primary language.

## What to avoid

- Stock-photo-style vagueness in written copy — mirrors avoiding decorative gradients in
  design: content should be specific to what the product actually does, not generic SaaS
  boilerplate ("Empower your team to unlock productivity").
- Long legal-sounding disclaimers on product pages outside the dedicated Terms/Privacy pages —
  keep product copy about the product; keep legal copy on its own pages.
- Padding a paragraph to look more substantial. If a sentence is the whole answer, that's the
  whole answer.
