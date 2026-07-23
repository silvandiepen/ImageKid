The shared product-page layout for the app family: hero with icon, status, and actions, a feature grid, alternating full-width sections, and cross-links to the sibling apps.

Pass a `ProductPageData` object via the required `data` prop (see `ProductPage.model.ts`). The availability status and the family cross-links are looked up from the app registry (`src/data/apps.ts`) by `data.id`, and the same id drives the `product-page--<id>` accent modifier styled in `src/styles/main.scss`.
