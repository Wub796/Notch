# Notch Marketing Website

This directory contains the production-ready static marketing website for Notch. It is 100% static, self-contained, and requires zero build step or external network calls at runtime.

## Deployment in Under 5 Steps

### Cloudflare Pages
1. Go to **Cloudflare Dashboard** → **Workers & Pages** → **Create application** → **Pages** → **Connect to Git**.
2. Select your repository (`Wub796/Notch`) and branch (`main`).
3. Set **Framework preset** to `None`.
4. Leave **Build command** empty (`None`) and set **Build output directory** to `/` (or `website` if deploying specifically from this folder).
5. Click **Save and Deploy**. `_headers` are applied automatically.

### Netlify
1. Go to **Netlify** → **Add new site** → **Import an existing project**.
2. Select repository and `main` branch.
3. Leave **Build command** empty and set **Publish directory** to `/` (or `website`).
4. Click **Deploy Notch**.

### GitHub Pages
1. In repository **Settings** → **Pages**.
2. Set Source to **Deploy from a branch**.
3. Select `main` and `/ (root)`.
4. Click **Save**.

## Files
- `index.html`: Semantic, responsive markup with JSON-LD schema & social preview meta.
- `404.html`: Custom macOS-styled error page.
- `_headers`: Caching and strict Content-Security-Policy headers for Cloudflare/Netlify.
- `robots.txt` & `sitemap.xml`: SEO crawl configuration.
- `css/styles.css`: Dark-mode tokens, continuous squircle notch curves, glassmorphism.
- `js/main.js`: Three.js floating MacBook 3D scene, GSAP scroll choreography, spring physics, and Web Audio synthesizer.
- `js/vendor/`: Pinned local dependencies (`three.module.min.js`, `gsap.min.js`, `ScrollTrigger.min.js`).
- `assets/`: App icons, favicons, and Open Graph preview image.
