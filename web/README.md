# ⚡ system-blueprint-os Studio (Web App)

> **Interactive Scope Risk Calculator, Failure-Mode Spec Generator, and Visual Architecture Studio.**

---

## 🚀 Instant Deployment to Vercel (1-Click)

This web application requires **zero build steps** and **zero node_modules** to run. It uses CDN-powered modern ES modules, Tailwind CSS, Lucide Icons, and Mermaid.js.

### Option 1: Import via Vercel Dashboard (Recommended)
1. Go to [https://vercel.com/new](https://vercel.com/new).
2. Connect your GitHub account and select this repository: `system-blueprint-os` (or `OpenBSA`).
3. Vercel will automatically read `vercel.json` from the root.
4. Click **Deploy**. Your studio will be live in ~10 seconds at `https://your-project.vercel.app`!

### Option 2: Deploy via Vercel CLI
```bash
# Inside this repository root:
vercel --prod
```

---

## 💻 Local Preview (No Server Required!)

Because this app is completely self-contained:
* Simply double-click `web/index.html` on your computer to open and use it in any modern web browser!
* Or run a lightweight local server if preferred:
  ```bash
  npx serve web
  ```

---

## 🛠️ Included Features
1. **Scope Risk & Budget Leakage Diagnostic:** 7-question interactive risk assessment calculating project failure probability (0-100%).
2. **Interactive Failure-Mode Spec Generator:** Select modules (Idempotency, RLS, Race Conditions) and instantly compile a developer-ready Markdown document to copy or download.
3. **Visual Architecture Studio:** Live-rendered Mermaid diagrams showing Multi-Tenant RLS, Payment Webhook loops, Four-Eyes approvals, and Circuit Breakers.
4. **Advisory & Consultation Link:** Direct call-to-action for Tri Raida's Business Systems Analysis consulting practice.
