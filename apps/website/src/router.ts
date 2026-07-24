import { createRouter, createWebHistory } from "vue-router";

import AcknowledgementsPage from "./pages/AcknowledgementsPage.vue";
import ArchitecturePage from "./pages/ArchitecturePage.vue";
import CutoutPage from "./pages/CutoutPage.vue";
import DocsIndexPage from "./pages/DocsIndexPage.vue";
import FeaturesPage from "./pages/FeaturesPage.vue";
import FekthorDocsPage from "./pages/FekthorDocsPage.vue";
import FekthorPage from "./pages/FekthorPage.vue";
import GettingStartedPage from "./pages/GettingStartedPage.vue";
import HomePage from "./pages/HomePage.vue";
import ImageKidDocsPage from "./pages/ImageKidDocsPage.vue";
import ImageKidPage from "./pages/ImageKidPage.vue";
import NotFoundPage from "./pages/NotFoundPage.vue";
import PrivacyPage from "./pages/PrivacyPage.vue";
import RoadmapPage from "./pages/RoadmapPage.vue";
import SupportPage from "./pages/SupportPage.vue";
import TermsPage from "./pages/TermsPage.vue";
import UpscalePage from "./pages/UpscalePage.vue";
import WorkflowsPage from "./pages/WorkflowsPage.vue";

export const router = createRouter({
  history: createWebHistory(),
  scrollBehavior: (to) => to.hash ? { el: to.hash } : { top: 0 },
  routes: [
    { path: "/", component: HomePage }, { path: "/features", component: FeaturesPage },
    { path: "/imagekid", component: ImageKidPage }, { path: "/fekthor", component: FekthorPage },
    { path: "/upscale", component: UpscalePage }, { path: "/cutout", component: CutoutPage },
    { path: "/docs", component: DocsIndexPage }, { path: "/docs/getting-started", component: GettingStartedPage },
    { path: "/docs/workflows", component: WorkflowsPage }, { path: "/docs/architecture", component: ArchitecturePage },
    { path: "/docs/roadmap", component: RoadmapPage },
    { path: "/docs/imagekid", component: ImageKidDocsPage },
    { path: "/docs/fekthor", component: FekthorDocsPage }, { path: "/support", component: SupportPage },
    { path: "/privacy", component: PrivacyPage }, { path: "/terms", component: TermsPage },
    { path: "/acknowledgements", component: AcknowledgementsPage },
    { path: "/not-found", component: NotFoundPage }, { path: "/:pathMatch(.*)*", redirect: "/not-found" }
  ]
});
