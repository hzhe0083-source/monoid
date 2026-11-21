///|
test "another product's words say its name, still.fail's hosts kept" {
  set_product("monoid")
  assert_eq(
    branded("still.fail cloud 在 app.still.fail，装 still.fail.app 或 https://still.fail/en；用 still.fail。"),
    "monoid cloud 在 app.still.fail，装 still.fail.app 或 https://still.fail/en；用 monoid。",
  )
  assert_eq(branded("noreply@still.fail (still.fail)"), "noreply@still.fail (monoid)")
  set_product("still.fail")
  assert_eq(branded("用 still.fail。"), "用 still.fail。")
  set_product("")
}

///|
test "another product's words say its command and home" {
  set_product("monoid")
  assert_eq(branded("启动：stillfail start"), "启动：monoid start")
  assert_eq(branded("`stillfail lock reset`"), "`monoid lock reset`")
  assert_eq(branded("~/.stillfail/run/update.log"), "~/.monoid/run/update.log")
  assert_eq(branded("stillfail-station-x.vbs"), "monoid-station-x.vbs")
  assert_eq(branded("a stillfail folder"), "a monoid folder")
  assert_eq(
    branded("stillfail-screen STILLFAIL_DATA @stillfail/ui stillfail.db stillfail/sf"),
    "stillfail-screen STILLFAIL_DATA @stillfail/ui stillfail.db stillfail/sf",
  )
  set_product("still.fail")
  assert_eq(branded("stillfail start"), "stillfail start")
  set_product("")
}
