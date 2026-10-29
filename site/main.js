const RELEASE = "https://github.com/Talkdedsec/tlk-patrol/releases/download/v0.1.0/";
const reduced = matchMedia("(prefers-reduced-motion: reduce)").matches;

// loader: short radio beat, then reveal
const ready = () => document.body.classList.add("is-ready");
if (reduced) ready();
// the hero video can stream in behind the page; waiting for window load held the loader for seconds
else setTimeout(ready, 650);

if (reduced) document.querySelector(".hero__video")?.pause();

// nav background after leaving the hero
const nav = document.querySelector(".nav");
const onScroll = () => nav.classList.toggle("is-solid", scrollY > innerHeight * 0.6);
addEventListener("scroll", onScroll, { passive: true });
onScroll();

// live clock in the hero
const clock = document.querySelector(".js-clock");
const tick = () => {
  const d = new Date();
  clock.textContent = `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
};
tick();
setInterval(tick, 15000);

// reveals and counters
const count = (el) => {
  const end = parseFloat(el.dataset.count);
  const dec = Number(el.dataset.dec || 0);
  if (reduced) return;
  const t0 = performance.now();
  const step = (t) => {
    const p = Math.min((t - t0) / 1400, 1);
    el.textContent = (end * (1 - Math.pow(1 - p, 4))).toFixed(dec);
    if (p < 1) requestAnimationFrame(step);
  };
  requestAnimationFrame(step);
};
const io = new IntersectionObserver((entries) => {
  for (const e of entries) {
    if (!e.isIntersecting) continue;
    e.target.classList.add("is-in");
    e.target.querySelectorAll("[data-count]").forEach(count);
    io.unobserve(e.target);
  }
}, { threshold: 0.2 });
document.querySelectorAll(".reveal").forEach((el) => io.observe(el));

// shift log: swap the sticky still with the active entry
const logItems = [...document.querySelectorAll(".shift__log li")];
const stills = [...document.querySelectorAll(".shift__media img")];
const shiftTime = document.querySelector(".js-shift-time");
const setShift = (li) => {
  logItems.forEach((x) => x.classList.toggle("is-on", x === li));
  stills.forEach((img) => img.classList.toggle("is-on", img.dataset.key === li.dataset.key));
  shiftTime.textContent = li.dataset.time;
};
const shiftIo = new IntersectionObserver((entries) => {
  for (const e of entries) if (e.isIntersecting) setShift(e.target);
}, { rootMargin: "-45% 0px -45% 0px" });
logItems.forEach((li) => shiftIo.observe(li));
setShift(logItems[0]);

// footage player: videos stream from the release assets
const player = document.querySelector(".player");
const video = document.querySelector(".js-player");
const title = document.querySelector(".js-title");
const tag = document.querySelector(".js-tag");
const items = [...document.querySelectorAll(".reel__item")];
let current = items[0];

const load = (item, play) => {
  current = item;
  items.forEach((x) => x.classList.toggle("is-active", x === item));
  video.poster = `media/${item.dataset.poster}`;
  video.src = RELEASE + item.dataset.src;
  title.textContent = item.dataset.title;
  tag.textContent = `REC 0${items.indexOf(item) + 1}`;
  if (play) video.play().catch(() => {});
  else player.classList.remove("is-playing");
};

document.querySelector(".js-start").addEventListener("click", () => {
  if (!video.src) load(current, true);
  else video.play().catch(() => {});
});
items.forEach((item) => item.addEventListener("click", () => {
  load(item, true);
  if (innerWidth < 960) player.scrollIntoView({ behavior: reduced ? "auto" : "smooth", block: "center" });
}));
video.addEventListener("play", () => player.classList.add("is-playing"));
video.addEventListener("ended", () => {
  const next = items[items.indexOf(current) + 1];
  if (next) load(next, true);
  else player.classList.remove("is-playing");
});
