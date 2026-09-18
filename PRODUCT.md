# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

- **Clientes (shoppers)**: end customers of a clothing store chain buying apparel online, using AR virtual try-on and an AI shopping assistant (chat widget) to decide on fit/style, and reserving items (`mis-reservas`).
- **Admin**: full back-office control — users, sucursales (store branches), proveedores (suppliers), inventario, catálogo maestro (productos, categorías, tallas, colores, temporadas, colecciones), reportes, and AI assistant configuration (`ia-config`).
- **Encargado** (branch/store manager): operational role scoped to one branch — inventory, reservations, stock movements, reports.
- **Proveedor** (supplier): external-facing role managing their own products and catalog listings feeding the store.

All four roles are served by the same Angular app (`frontend-web`), route-guarded by role (`adminGuard`, `encargadoGuard`, `proveedorGuard`, `authGuard`, `guestGuard`).

## Product Purpose

SmartLook-AI is an intelligent e-commerce platform for a clothing store chain. It exists to let shoppers buy apparel online with more confidence than a typical online clothing store, via AR virtual fitting rooms (try on garments virtually) and AI features (assistant chat, and configurable AI provider/model in the admin panel). Success = a working MVP demonstrating the full commerce loop (browse catalog → try on via AR → reserve/buy) plus the operational back-office (inventory, suppliers, branches, reports) end-to-end.

## Positioning

Not a generic storefront built on Shopify/Magento/WooCommerce/PrestaShop (explicitly excluded by the academic brief) — a custom-built platform whose differentiator is AR virtual try-on combined with an AI shopping assistant, layered over a real multi-role retail operation (branches, suppliers, inventory, reservations) rather than a single-seller storefront.

## Operating Context

- Academic capstone project (Sistemas II, "Examen 1"), built by a 2-person team over ~4 weeks. Final presentation/defense: 2026-09-20 / 2026-09-22.
- Deployed to the cloud (not localhost) per the assignment brief; local dev via Docker Compose (`docker compose up -d`, backend on :8000, frontend on :4200) or manual `npm start` / `uvicorn`.
- Backend: Python + FastAPI, modular monolith by business domain (`auth`, `usuarios`, `sucursales`, `catalogo`, `inventario`, `reservas`, `ventas`, `pagos`, `ia`, `reportes`). Frontend: Angular (standalone components, SCSS, no UI framework). Mobile: separate Flutter app (`mobile-app`, largely unscaffolded) — out of scope for this frontend-web redesign. DB: PostgreSQL via Supabase.
- Methodology: PUDS, modeled with UML 2.5+; heavy academic documentation lives in `docs/`.

## Capabilities and Constraints

- Confirmed: multi-role auth, product catalog (products/categories/sizes/colors/seasons/collections), inventory, branches, suppliers, reservations, reports, an AI chat assistant for clientes, and an admin-configurable AI provider (Ollama local / OpenAI / Groq presets).
- Constraint: must not be built on an existing e-commerce framework (PrestaShop/Shopify/Magento/WooCommerce) — everything here is bespoke.
- Constraint: known Windows+Docker Vite hot-reload quirk on a few "core" frontend files (`app.config.ts`, `app.ts`, `main.ts`, `app.routes.ts`) — requires `docker compose restart frontend` to see changes; feature-level component files hot-reload fine.
- Undecided/not yet built: actual payment gateway integration and real AR try-on rendering appear to be in-progress/planned per the domain module list (`pagos`, and AR is mentioned in the README) rather than fully implemented in the current frontend surfaces surveyed.

## Brand Commitments

- Name: **SmartLook-AI** (wordmark currently rendered as "SmartLook**.AI**" with a gradient-accent suffix). No other fixed brand asset (logo mark, mandated color, mandated font) exists yet — current favicon is still the unmodified Angular CLI default, confirming no locked visual identity.
- The user has explicit freedom to define a new color palette, typography, and a more "real e-commerce, professional, 3D" visual language; nothing about the current warm-pastel/editorial-serif look is a binding constraint.

## Evidence on Hand

- No product photography, real garment imagery, customer testimonials, case studies, or press exists — this is a student MVP, not a live retailer. Redesign work must not fabricate customer quotes, review counts, press logos, or real-brand product photos; use neutral/placeholder or generated imagery instead, clearly non-deceptive.
- Existing implemented UI (all of `frontend-web/src/app/features/**` and `core/components/**`) is the current visual state and is being fully replaced, not preserved, per explicit user request.

## Product Principles

1. Every role (cliente, admin, encargado, proveedor) is a first-class surface — the redesign must not treat internal back-office panels as an afterthought to the storefront.
2. The differentiator (AR try-on + AI assistant) should read as a premium, trustworthy capability, not a gimmick — professional retail polish first, novelty second.
3. Built bespoke, not on a commerce framework — the UI should not read as a generic templated storefront; it should look purpose-built.
4. MVP scope under an academic deadline: prioritize a coherent, complete design system applied consistently over any single hyper-polished one-off page.

## Accessibility & Inclusion

No product-specific accessibility requirement was established by the user; apply standard WCAG AA-level practices (contrast, focus states, semantic structure) as general craft floor.
