const KEY = "moontoml-theme";
const root = document.documentElement;

const toggle = document.querySelector(".theme");
if (toggle) {
  toggle.addEventListener("click", () => {
    const next = root.dataset.theme === "dark" ? "light" : "dark";
    root.dataset.theme = next;
    try {
      localStorage.setItem(KEY, next);
    } catch (e) {
      /* private mode */
    }
  });
}

const links = Array.from(document.querySelectorAll(".index a[href^='#']"));
const targets = links
  .map((a) => document.querySelector(a.getAttribute("href")))
  .filter((el) => el);

if (targets.length && "IntersectionObserver" in window) {
  const obs = new IntersectionObserver(
    (entries) => {
      const visible = entries
        .filter((e) => e.isIntersecting)
        .sort((a, b) => a.boundingClientRect.top - b.boundingClientRect.top);
      if (!visible[0]) return;
      const id = "#" + visible[0].target.id;
      for (const a of links) {
        a.classList.toggle("active", a.getAttribute("href") === id);
      }
    },
    { rootMargin: "-12% 0px -78% 0px", threshold: 0 },
  );
  for (const t of targets) obs.observe(t);
}
