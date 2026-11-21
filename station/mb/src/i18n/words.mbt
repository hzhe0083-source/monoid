// The words people read, in their language (station/src/ops/i18n.ts `tr`): the station part of client/i18n/catalog,
// zh and en, as each package holds it (`JV`, `JValue` or a parsed `Json` map). `{name}` takes the value given as
// `name`; `{"one", "other"}` is chosen by `n` (`String(n).trim() === "1"`: one). A key a language lacks is said in
// Chinese; one neither has is the key. Where the station's cloud is another product's, still.fail's name standing
// alone is that product's (client/i18n/brand.ts `branded`).

///|
/// `\w`: an ASCII letter, digit or `_`.
fn word_char(c : Int) -> Bool {
  (c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_'
}

///|
/// still.fail's name standing alone made `product`'s: not after [\w./@-], not before [\w-] or a `.` and a \w.
pub fn branded(text : String, product : String) -> String {
  if product == "still.fail" {
    return text
  }
  commanded(named(text, product), product)
}

///|
/// Whether `text` holds `word` at `i`.
fn holds(text : String, i : Int, word : String) -> Bool {
  i >= 0 && i + word.length() <= text.length() && text.unsafe_substring(start=i, end=i + word.length()) == word
}

///|
/// still.fail's command and home made `product`'s where it is a plain word (monoid: `monoid start`, ~/.monoid), as
/// client/i18n/brand.ts COMMAND: `stillfail` standing alone, after `~/.`, or before `-station`; never a part of a
/// longer name (stillfail-screen, STILLFAIL_DATA, @stillfail/ui, stillfail.db).
fn commanded(text : String, product : String) -> String {
  let plain = product.length() > 0 &&
    product.to_array().iter().all(fn(c) { (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') })
  if !plain || !text.contains("stillfail") {
    return text
  }
  let word = "stillfail"
  let out = StringBuilder::new()
  let mut i = 0
  while i < text.length() {
    if holds(text, i, word) {
      let j = i + word.length()
      let c0 = if i > 0 { text.unsafe_charcode_at(i - 1) } else { 0 }
      let c1 = if j < text.length() { text.unsafe_charcode_at(j) } else { 0 }
      let home = i >= 3 && c0 == '.' && (holds(text, i - 3, "~/") || holds(text, i - 3, "~\\"))
      let ok = if home {
        !(word_char(c1) || c1 == '.' || c1 == '-')
      } else {
        !(word_char(c0) || c0 == '.' || c0 == '/' || c0 == '@' || c0 == '\\' || c0 == '~' || c0 == '-') &&
        (
          !(word_char(c1) || c1 == '.' || c1 == '/' || c1 == '@' || c1 == '\\' || c1 == '-') ||
          holds(text, j, "-station")
        )
      }
      if ok {
        out.write_string(product)
        i = j
        continue
      }
    }
    out.write_char(text.unsafe_charcode_at(i).unsafe_to_char())
    i += 1
  }
  out.to_string()
}

///|
/// still.fail's name standing alone made `product`'s.
fn named(text : String, product : String) -> String {
  if !text.contains("still.fail") {
    return text
  }
  let name = "still.fail"
  let out = StringBuilder::new()
  let mut i = 0
  while i < text.length() {
    if i + name.length() <= text.length() && text.unsafe_substring(start=i, end=i + name.length()) == name {
      let before_ok = i == 0 ||
        {
          let c = text.unsafe_charcode_at(i - 1)
          !(word_char(c) || c == '.' || c == '/' || c == '@' || c == '-')
        }
      let j = i + name.length()
      let after_ok = j >= text.length() ||
        {
          let c = text.unsafe_charcode_at(j)
          !(word_char(c) || c == '-' || (c == '.' && j + 1 < text.length() && word_char(text.unsafe_charcode_at(j + 1))))
        }
      if before_ok && after_ok {
        out.write_string(product)
        i = j
        continue
      }
    }
    out.write_char(text.unsafe_charcode_at(i).unsafe_to_char())
    i += 1
  }
  out.to_string()
}

///|
/// `{name}` filled; one not given, and a `{` that opens no name, left as they are.
pub fn fill(text : String, args : Array[(String, String)]) -> String {
  if args.length() == 0 || !text.contains("{") {
    return text
  }
  let out = StringBuilder::new()
  let mut i = 0
  while i < text.length() {
    let c = text.unsafe_charcode_at(i)
    if c == '{' {
      let mut j = i + 1
      while j < text.length() && word_char(text.unsafe_charcode_at(j)) {
        j += 1
      }
      if j < text.length() && text.unsafe_charcode_at(j) == '}' {
        let name = text.unsafe_substring(start=i + 1, end=j)
        match args.search_by(a => a.0 == name) {
          Some(k) => {
            out.write_string(args[k].1)
            i = j + 1
            continue
          }
          None => ()
        }
      }
    }
    out.write_char(c.unsafe_to_char())
    i += 1
  }
  out.to_string()
}

///|
/// A plural's words: `one` where `n` is 1, else `other`; `other` where `one` is missing, the key where both are.
fn plural(one : String?, other : String?, key : String, args : Array[(String, String)]) -> String {
  let is_one = match args.search_by(a => a.0 == "n") {
    Some(i) => @jsjson.trim_js(args[i].1) == "1"
    None => false
  }
  match (if is_one { one } else { other }) {
    Some(t) => t
    None => other.unwrap_or(key)
  }
}

///|
/// The words of `key` in `lang` from catalogs of `@jsjson.JV`.
pub fn tr_jv(
  zh : @jsjson.JV,
  en : @jsjson.JV,
  product : String,
  lang : String,
  key : String,
  args? : Array[(String, String)] = [],
) -> String {
  let found = match @jsjson.jget(Some(if lang == "en" { en } else { zh }), key) {
    Some(f) => Some(f)
    None => @jsjson.jget(Some(zh), key)
  }
  let text = match found {
    Some(Str(u)) => u
    Some(Obj(_) as f) => plural(@jsjson.jstr(f.get("one")), @jsjson.jstr(f.get("other")), key, args)
    _ => key
  }
  fill(branded(text, product), args)
}

///|
/// The words of `key` in `lang` from catalogs of `@jsjson.JValue`.
pub fn tr_jvalue(
  zh : @jsjson.JValue,
  en : @jsjson.JValue,
  product : String,
  lang : String,
  key : String,
  args? : Array[(String, String)] = [],
) -> String {
  let found = match @jsjson.jval_at(Some(if lang == "en" { en } else { zh }), key) {
    Some(f) => Some(f)
    None => @jsjson.jval_at(Some(zh), key)
  }
  let text = match found {
    Some(Str(u)) => @jsjson.sanitize_str(u)
    Some(Obj(_) as f) => plural(@jsjson.jval_str_of(f.get("one")), @jsjson.jval_str_of(f.get("other")), key, args)
    _ => key
  }
  fill(branded(text, product), args)
}

///|
/// The words of `key` in `lang` from parsed catalogs (`Json` objects' maps).
pub fn tr_json(
  zh : Map[String, Json],
  en : Map[String, Json],
  lang : String,
  key : String,
  args? : Array[(String, String)] = [],
  product? : String = "still.fail",
) -> String {
  let found = match (if lang == "en" { en.get(key) } else { None }) {
    Some(f) => Some(f)
    None => zh.get(key)
  }
  let str = (v : Json?) => match v {
    Some(String(s)) => Some(s)
    _ => None
  }
  let text = match found {
    Some(String(s)) => s
    Some(Object(o)) => plural(str(o.get("one")), str(o.get("other")), key, args)
    _ => key
  }
  fill(branded(text, product), args)
}
