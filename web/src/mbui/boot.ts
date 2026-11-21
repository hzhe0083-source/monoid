// The mark mbui.html shows from its first paint while the app comes (`#boot`: its font, mbui's host and the app's
// script on their way), taken away once the app's first frame is on the canvas, so nothing of it is left to lay out or
// draw after. A load that fails, or that takes far longer than it should, says so under the mark with a way to load the
// page again, as an app on the home screen has no reload of its own.
import { productOf } from "../../../client/i18n/brand.ts";
import { chineseFor } from "./gpu.ts";

/** How long a load may take before the page offers to load it again (index.html's splash waits as long). */
const WAIT_MS = 15_000;
let waiting = 0;

const boot = (): HTMLElement | null => document.getElementById("boot");

function zh(): boolean {
  let kept: string | null = null;
  try {
    kept = localStorage.getItem("stillfail.prefs");
  } catch {
    kept = null;
  }
  return chineseFor(navigator.language || "", kept);
}

/** Under the mark: what happened and 重新加载 (said once). */
function offerReload(failed: boolean): void {
  const b = boot();
  if (!b || b.querySelector(".again")) return;
  const z = zh();
  // (the product this host is: monoid on monoid's, client/i18n/brand.ts)
  const name = productOf(location.hostname).name;
  const said = document.createElement("p");
  said.className = "said";
  said.textContent = failed
    ? z ? `${name} 没有加载完成，检查网络后重新加载。` : `${name} did not finish loading. Check the connection and load it again.`
    : z ? "加载得比平常久，可以重新加载。" : "This is taking longer than usual.";
  const again = document.createElement("button");
  again.type = "button";
  again.className = "again";
  again.textContent = z ? "重新加载" : "Reload";
  again.onclick = () => location.reload();
  b.classList.add("stuck");
  b.append(said, again);
}

/** The load has begun: offered again once it has taken too long (timer: a deadline). */
export function bootWaits(): void {
  clearTimeout(waiting);
  waiting = window.setTimeout(() => offerReload(false), WAIT_MS);
}

/** What the app needs did not come (a script that did not load, one that threw as it ran). */
export function bootFailed(): void {
  clearTimeout(waiting);
  offerReload(true);
}

/** Taken away from the page at once (the guide put up in the app's place). */
export function bootGone(): void {
  clearTimeout(waiting);
  boot()?.remove();
}

/** The bare ground left (bootMarkOut) faded off what the app's first frame drew, so the app comes in from the ground
 *  rather than at a cut (the app's first screen has no way in of its own); at once where motion is reduced or the page
 *  is not shown. Then out of the page, whether or not the fade was seen. */
function groundOff(): void {
  clearTimeout(waiting);
  const b = boot();
  if (!b) return;
  if (document.documentElement.hasAttribute("data-reduced-motion") || document.visibilityState !== "visible") {
    b.remove();
    return;
  }
  b.classList.add("gone");
  // (mbui.html's #boot.gone: its fade's time)
  setTimeout(() => b.remove(), 160);
}

/** A script's bytes fetched ahead (a preload, which the script of the same address then takes as it is added), so that
 *  all the waiting for the network is done while the mark shows, never once the mark has gone; done when it came or
 *  did not (the script added then says which). */
export function fetchedAhead(src: string): Promise<void> {
  return new Promise((done) => {
    const l = document.createElement("link");
    l.rel = "preload";
    l.as = "script";
    l.href = src;
    l.onload = () => done();
    l.onerror = () => done();
    document.head.appendChild(l);
  });
}

/** The mark faded out on the bare ground before the app runs, so it is never drawn over what the app draws: the app's
 *  first screen then comes in by its own fade from that same ground. At once where it was not seen yet (a load from
 *  the cache, still in its first 240 ms), where motion is reduced or where the page is not shown. */
export function bootMarkOut(): Promise<void> {
  clearTimeout(waiting);
  const mark = boot()?.querySelector<HTMLElement>(".mark");
  if (!mark) return Promise.resolve();
  const seen = Number.parseFloat(getComputedStyle(mark).opacity) || 0;
  // (from where it is: its way in, and the light over it, stopped there)
  mark.style.animation = "none";
  mark.style.opacity = String(seen);
  mark.classList.add("still");
  if (seen <= 0.02 || document.documentElement.hasAttribute("data-reduced-motion") || document.visibilityState !== "visible") {
    mark.style.opacity = "0";
    return Promise.resolve();
  }
  return new Promise((done) => {
    let over = 0;
    const end = () => {
      clearTimeout(over);
      mark.removeEventListener("transitionend", end);
      done();
    };
    mark.addEventListener("transitionend", end);
    // (timer: a deadline, should the browser tell no end: a page hidden meanwhile)
    over = window.setTimeout(end, 160);
    void mark.offsetWidth;
    mark.style.transition = "opacity 100ms ease-out";
    mark.style.opacity = "0";
  });
}

interface Presents { present(...args: unknown[]): unknown }

/** Taken away as the app's first frame is drawn (mbui's host draws every frame through `present`, which the app
 *  calls by name each time: host_js.mbt js_present): the host's own `present` is put back by that first call, so no
 *  frame after it runs anything of this. What is taken away is the bare ground by then (bootMarkOut): nothing of the
 *  mark is ever drawn over the app. */
export function bootGoesWithFirstFrame(host: Presents | undefined): void {
  if (!host || typeof host.present !== "function") {
    bootGone();
    return;
  }
  const present = host.present;
  host.present = function (this: unknown, ...args: unknown[]) {
    host.present = present;
    const drawn = present.apply(this, args);
    // (the canvas shows what was drawn as the browser paints this frame: the ground goes from the one after)
    requestAnimationFrame(groundOff);
    return drawn;
  };
}
