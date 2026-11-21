// Which product the words are for. The same code is two products: still.fail, and monoid (the company's, its cloud on
// monoid.build: cloud/deploy.py CLOUDS). The catalog says still.fail; where the cloud is another product's, its words say
// that product's name instead (`branded`), as the core, the station, the cloud and the apps read them. Hosts
// (app.still.fail) and what agents are told stay as they are.

export interface Product {
  /** Its name. */
  name: string;
  /** Its test channel's (still.fail's on youdid.wtf, monoid's on monoid.zone). */
  test: string;
  /** Its name in a program's, a directory's or a service's (stillfail: ~/.stillfail, `stillfail`, stillfail-station.service). */
  id: string;
  /** Its reversed domain, a bundle's or a launchd label's (fail.still.station). */
  reverse: string;
}

export const STILLFAIL: Product = { name: "still.fail", test: "youdid.wtf", id: "stillfail", reverse: "fail.still" };

/** Each product other than still.fail: the domains its clouds are on, its names. */
export const PRODUCTS: { zones: string[]; product: Product }[] = [
  { zones: ["monoid.build", "monoid.zone"], product: { name: "monoid", test: "monoid.zone", id: "monoid", reverse: "build.monoid" } },
];

/** The product whose cloud is at `origin` (a URL, or a bare host): still.fail's for any other, a local cloud's too. */
export function productOf(origin: string): Product {
  let host = origin;
  try {
    host = new URL(origin).hostname;
  } catch {
    // (a bare host)
  }
  return PRODUCTS.find((p) => p.zones.some((zone) => host === zone || host.endsWith("." + zone)))?.product ?? STILLFAIL;
}

/** The name still.fail standing alone (not a host or an address: app.still.fail, https://still.fail, noreply@still.fail, still.fail.app). */
const NAME = /(?<![\w./@-])still\.fail(?![\w-]|\.\w)/g;

/** still.fail's command and home as people are told them (`stillfail start`, ~/.stillfail/run, stillfail-station.service):
 * the word standing alone, or after `~/.`, or before `-station`. Not a part of a longer name (stillfail-screen,
 * STILLFAIL_DATA, @stillfail/ui, stillfail.db): those are every product's. */
const COMMAND = /(?<=~[/\\]\.)stillfail(?![\w.-])|(?<![\w./@\\~-])stillfail(?![\w./@\\]|-(?!station))/g;

/** `text` with still.fail's name `product`'s, and its command and home `product`'s (its id's: `monoid start`, ~/.monoid). */
export function branded(text: string, product: Product): string {
  if (product === STILLFAIL) return text;
  const named = text.includes("still.fail") ? text.replace(NAME, product.name) : text;
  return named.includes("stillfail") ? named.replace(COMMAND, product.id) : named;
}
