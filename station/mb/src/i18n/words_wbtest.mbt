///|
fn jv_catalog(entries : Array[(String, @jsjson.JV)]) -> @jsjson.JV {
  @jsjson.jobj(entries)
}

///|
test "branded: still.fail standing alone only" {
  let p = "Acme"
  assert_eq(branded("still.fail", p), "Acme")
  assert_eq(branded("用 still.fail 吧", p), "用 Acme 吧")
  assert_eq(branded("still.fail.", p), "Acme.")
  assert_eq(branded("(still.fail)", p), "(Acme)")
  assert_eq(branded("app.still.fail", p), "app.still.fail")
  assert_eq(branded("still.fail/docs", p), "Acme/docs")
  assert_eq(branded("https://still.fail/docs", p), "https://still.fail/docs")
  assert_eq(branded("a@still.fail", p), "a@still.fail")
  assert_eq(branded("still.fail-x", p), "still.fail-x")
  assert_eq(branded("still.fail.app", p), "still.fail.app")
  assert_eq(branded("x-still.fail", p), "x-still.fail")
  assert_eq(branded("still.failing", p), "still.failing")
  assert_eq(branded("still.fail and still.fail", p), "Acme and Acme")
  assert_eq(branded("still.fail", "still.fail"), "still.fail")
  assert_eq(branded("nothing here", p), "nothing here")
}

///|
test "branded: still.fail's command and home, for a product of a plain name" {
  assert_eq(branded("启动：stillfail start", "monoid"), "启动：monoid start")
  assert_eq(branded("~/.stillfail/run/update.log", "monoid"), "~/.monoid/run/update.log")
  assert_eq(branded("stillfail-station-x.vbs", "monoid"), "monoid-station-x.vbs")
  assert_eq(
    branded("stillfail-screen STILLFAIL_DATA @stillfail/ui stillfail.db stillfail/sf", "monoid"),
    "stillfail-screen STILLFAIL_DATA @stillfail/ui stillfail.db stillfail/sf",
  )
  assert_eq(branded("stillfail start", "Acme"), "stillfail start")
  assert_eq(branded("stillfail start", "still.fail"), "stillfail start")
}

///|
test "fill: names given, others left" {
  assert_eq(fill("{a} and {b}", [("a", "1"), ("b", "2")]), "1 and 2")
  assert_eq(fill("{a} and {missing}", [("a", "1")]), "1 and {missing}")
  assert_eq(fill("{ a} {a-b} {", [("a", "1")]), "{ a} {a-b} {")
  assert_eq(fill("{a}{a}", [("a", "{a}")]), "{a}{a}")
  assert_eq(fill("{x_1}", [("x_1", "y")]), "y")
  assert_eq(fill("{a}", []), "{a}")
  assert_eq(fill("no braces", [("a", "1")]), "no braces")
}

///|
test "tr_jv: language, Chinese for a key English lacks, the key for neither" {
  let zh = jv_catalog([("k", @jsjson.js("中 {name}")), ("only.zh", @jsjson.js("仅中文"))])
  let en = jv_catalog([("k", @jsjson.js("en {name}"))])
  let args = [("name", "x")]
  assert_eq(tr_jv(zh, en, "still.fail", "en", "k", args~), "en x")
  assert_eq(tr_jv(zh, en, "still.fail", "zh", "k", args~), "中 x")
  assert_eq(tr_jv(zh, en, "still.fail", "fr", "k", args~), "中 x")
  assert_eq(tr_jv(zh, en, "still.fail", "en", "only.zh"), "仅中文")
  assert_eq(tr_jv(zh, en, "still.fail", "en", "nope"), "nope")
}

///|
test "tr_jv: plurals by n, branded" {
  let p = @jsjson.jobj([("one", @jsjson.js("{n} still.fail item")), ("other", @jsjson.js("{n} still.fail items"))])
  let o = @jsjson.jobj([("other", @jsjson.js("{n} things"))])
  let none = @jsjson.jobj([])
  let zh = jv_catalog([("p", p), ("o", o), ("none", none)])
  let en = jv_catalog([])
  assert_eq(tr_jv(zh, en, "Acme", "en", "p", args=[("n", "1")]), "1 Acme item")
  assert_eq(tr_jv(zh, en, "Acme", "en", "p", args=[("n", " 1\u{3000}")]), " 1\u{3000} Acme item")
  assert_eq(tr_jv(zh, en, "Acme", "en", "p", args=[("n", "2")]), "2 Acme items")
  assert_eq(tr_jv(zh, en, "Acme", "en", "p"), "{n} Acme items")
  assert_eq(tr_jv(zh, en, "Acme", "en", "o", args=[("n", "1")]), "1 things")
  assert_eq(tr_jv(zh, en, "Acme", "en", "none", args=[("n", "1")]), "none")
}

///|
test "tr_jvalue: as tr_jv" {
  let zh = @jsjson.parse(
    "{\"k\":\"中 {name}\",\"p\":{\"one\":\"{n} 个\",\"other\":\"{n} 些\"},\"b\":\"用 still.fail\"}",
  ) catch {
    _ => panic()
  }
  let en = @jsjson.parse("{\"k\":\"en {name}\"}") catch { _ => panic() }
  assert_eq(tr_jvalue(zh, en, "still.fail", "en", "k", args=[("name", "x")]), "en x")
  assert_eq(tr_jvalue(zh, en, "still.fail", "zh", "k", args=[("name", "x")]), "中 x")
  assert_eq(tr_jvalue(zh, en, "still.fail", "en", "p", args=[("n", "1")]), "1 个")
  assert_eq(tr_jvalue(zh, en, "still.fail", "en", "p", args=[("n", "3")]), "3 些")
  assert_eq(tr_jvalue(zh, en, "Acme", "en", "b"), "用 Acme")
  assert_eq(tr_jvalue(zh, en, "still.fail", "en", "nope"), "nope")
}

///|
test "tr_json: as tr_jv, still.fail unless a product is given" {
  let zh : Map[String, Json] = {
    "k": "中 {name}",
    "p": { "one": "{n} 个", "other": "{n} 些" },
    "b": "用 still.fail",
    "bad": { "one": 1, "other": 2 },
  }
  let en : Map[String, Json] = { "k": "en {name}" }
  assert_eq(tr_json(zh, en, "en", "k", args=[("name", "x")]), "en x")
  assert_eq(tr_json(zh, en, "zh", "k", args=[("name", "x")]), "中 x")
  assert_eq(tr_json(zh, en, "en", "p", args=[("n", "1")]), "1 个")
  assert_eq(tr_json(zh, en, "en", "p", args=[("n", "0")]), "0 些")
  assert_eq(tr_json(zh, en, "en", "b"), "用 still.fail")
  assert_eq(tr_json(zh, en, "en", "b", product="Acme"), "用 Acme")
  assert_eq(tr_json(zh, en, "en", "bad", args=[("n", "1")]), "bad")
  assert_eq(tr_json(zh, en, "en", "nope"), "nope")
}
