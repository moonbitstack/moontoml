import { createRoot } from "react-dom/client";
import { Home } from "./home";
import { Guide } from "./guide";

const root = document.getElementById("root");
if (root) {
  const page = document.body.dataset.page;
  createRoot(root).render(page === "guide" ? <Guide /> : <Home />);
}
