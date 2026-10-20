// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// What created a path, which is what decides whether touching it again is legal.
///
/// TOML's redefinition rules are not one rule but several, and they turn on how a
/// table came to exist: one opened by a header may be extended by dotted keys under
/// it, one created by a dotted key may not later be opened by a header, and an
/// inline table is closed the moment its brace does.
priv enum Kind {
  Direct
  Header
  Dotted
  Inline
  Tables
}

///|
/// Where the reader is and what it has built.
priv struct Reader {
  src : StringView
  mut pos : Int32
  mut line : Int32
  mut bol : Int32
  flavor : Flavor
  root : Map[String, Json]
  // The table that bare keys land in, and its dotted path.
  mut here : Map[String, Json]
  mut prefix : String
  // How each dotted path came to exist.
  seen : Map[String, Kind]
}

///|
fn Reader::new(src : StringView, flavor : Flavor) -> Reader {
  let root : Map[String, Json] = Map([])
  {
    src,
    pos: 0,
    line: 1,
    bol: 0,
    flavor,
    root,
    here: root,
    prefix: "",
    seen: Map([]),
  }
}

// -- the cursor ---------------------------------------------------------------

///|
fn Reader::at(self : Reader) -> At {
  { at: self.pos, line: self.line, column: self.pos - self.bol + 1, }
}

///|
fn Reader::eof(self : Reader) -> Bool {
  self.pos >= self.src.length()
}

///|
fn Reader::cur(self : Reader) -> Int32 {
  if self.pos < self.src.length() {
    self.src[self.pos].to_int()
  } else {
    -1
  }
}

///|
fn Reader::ahead(self : Reader, k : Int32) -> Int32 {
  if self.pos + k < self.src.length() {
    self.src[self.pos + k].to_int()
  } else {
    -1
  }
}

///|
fn Reader::bump(self : Reader) -> Unit {
  if self.pos >= self.src.length() {
    return
  }
  let c = self.src[self.pos].to_int()
  self.pos = self.pos + 1
  if c == 0x0a {
    self.line = self.line + 1
    self.bol = self.pos
  }
}

///|
/// Skip spaces and tabs, which TOML allows anywhere between tokens.
fn Reader::gap(self : Reader) -> Unit {
  while self.cur() == 0x20 || self.cur() == 0x09 {
    self.bump()
  }
}

///|
/// Skip whitespace, comments and line breaks, up to the next thing that means
/// something.
fn Reader::skip(self : Reader) -> Unit {
  for ;; {
    self.gap()
    if self.cur() == 0x23 {
      while !self.eof() && self.cur() != 0x0a {
        self.bump()
      }
      continue
    }
    if self.cur() == 0x0a || self.cur() == 0x0d {
      self.bump()
      continue
    }
    return
  }
}

///|
/// Everything to the end of the line must be a comment or nothing.
fn Reader::end_of_line(self : Reader) -> Unit raise Refused {
  self.gap()
  if self.cur() == 0x23 {
    while !self.eof() && self.cur() != 0x0a {
      self.bump()
    }
    return
  }
  if self.eof() || self.cur() == 0x0a || self.cur() == 0x0d {
    return
  }
  raise Trailing(self.at())
}

///|
fn Reader::printable(self : Reader) -> Char {
  if self.eof() {
    ' '
  } else {
    self.src[self.pos].unsafe_to_char()
  }
}

// -- the document -------------------------------------------------------------

///|
/// The whole document: a run of key-value pairs and table headers.
fn Reader::document(self : Reader) -> Json raise Refused {
  for ;; {
    self.skip()
    if self.eof() {
      break
    }
    if self.cur() == 0x5b {
      self.header()
      continue
    }
    self.pair()
  }
  Json::object(self.root)
}

///|
/// A `[table]` or `[[array of tables]]` header (§Table, §Array of Tables).
fn Reader::header(self : Reader) -> Unit raise Refused {
  let at = self.at()
  self.bump()
  let array = self.cur() == 0x5b
  if array {
    self.bump()
  }
  let path = self.path()
  self.gap()
  if self.cur() != 0x5d {
    raise Unexpected(self.at(), self.printable())
  }
  self.bump()
  if array {
    if self.cur() != 0x5d {
      raise Unexpected(self.at(), self.printable())
    }
    self.bump()
  }
  self.end_of_line()
  self.here = if array {
    self.open_tables(path, at)
  } else {
    self.open_table(path, at)
  }
  self.prefix = join(path)
}

///|
/// Walk to the table `path` names, creating what is missing, and mark it opened.
fn Reader::open_table(
  self : Reader,
  path : Array[String],
  at : At,
) -> Map[String, Json] raise Refused {
  let full = join(path)
  // A header may not repeat, and may not open something a dotted key already made,
  // a value already took, or an inline table closed.
  match self.seen.get(full) {
    Some(Header) | Some(Direct) | Some(Dotted) | Some(Inline) =>
      raise Redefined(at, full)
    _ => ()
  }
  let table = self.walk(path, at)
  self.seen[full] = Header
  table
}

///|
/// The same for `[[…]]`, which appends a table to an array rather than opening one.
fn Reader::open_tables(
  self : Reader,
  path : Array[String],
  at : At,
) -> Map[String, Json] raise Refused {
  let parent = self.walk(path[0:path.length() - 1].to_owned(), at)
  let name = path[path.length() - 1]
  let full = join(path)
  match self.seen.get(full) {
    Some(Tables) | None => ()
    Some(_) => raise Redefined(at, full)
  }
  self.seen[full] = Tables
  let fresh : Map[String, Json] = Map([])
  match parent.get(name) {
    Some(Array(items)) => {
      items.push(Json::object(fresh))
      ()
    }
    Some(_) => raise Redefined(at, full)
    None => parent[name] = Json::array([Json::object(fresh)])
  }
  fresh
}

///|
/// Walk `path` from the root, creating tables as needed, and answer the last one.
///
/// Walking into an array of tables lands in its last element, which is what makes
/// `[[a]]` followed by `[a.b]` put `b` inside the table just appended.
fn Reader::walk(
  self : Reader,
  path : Array[String],
  at : At,
) -> Map[String, Json] raise Refused {
  let mut table = self.root
  let mut so_far = ""
  for i = 0; i < path.length(); i = i + 1 {
    let name = path[i]
    so_far = if so_far == "" { name } else { so_far + "." + name }
    match table.get(name) {
      Some(Object(inner)) => {
        if self.seen.get(so_far) is Some(Inline) {
          raise Redefined(at, so_far)
        }
        table = inner
      }
      Some(Array(items)) =>
        if self.seen.get(so_far) is Some(Tables) && items.length() > 0 {
          match items[items.length() - 1] {
            Object(inner) => table = inner
            _ => raise Redefined(at, so_far)
          }
        } else {
          raise Redefined(at, so_far)
        }
      Some(_) => raise Redefined(at, so_far)
      None => {
        // A table created on the way to somewhere else is implicit and stays
        // unmarked, so its own header may still open it later (§Table).
        let fresh : Map[String, Json] = Map([])
        table[name] = Json::object(fresh)
        table = fresh
      }
    }
  }
  table
}

///|
/// One `key = value` line, where the key may be dotted.
fn Reader::pair(self : Reader) -> Unit raise Refused {
  let at = self.at()
  let path = self.path()
  self.gap()
  if self.cur() != 0x3d {
    raise Unexpected(self.at(), self.printable())
  }
  self.bump()
  self.gap()
  let value = self.value(0)
  self.end_of_line()
  // A dotted key walks into tables under the current one; the last segment is the
  // key itself.
  let mut table = self.here
  let mut so_far = self.prefix
  for i = 0; i < path.length() - 1; i = i + 1 {
    let name = path[i]
    so_far = if so_far == "" { name } else { so_far + "." + name }
    match table.get(name) {
      Some(Object(inner)) => {
        // A dotted key may extend a table it made itself, but not one that a
        // header opened or an inline table closed.
        match self.seen.get(so_far) {
          Some(Inline) | Some(Header) => raise Redefined(at, so_far)
          _ => ()
        }
        table = inner
      }
      Some(_) => raise Redefined(at, so_far)
      None => {
        let fresh : Map[String, Json] = Map([])
        table[name] = Json::object(fresh)
        self.seen[so_far] = Dotted
        table = fresh
      }
    }
  }
  let name = path[path.length() - 1]
  let full = if so_far == "" { name } else { so_far + "." + name }
  if table.get(name) is Some(_) {
    raise Redefined(at, full)
  }
  table[name] = value
  self.seen[full] = if value is Object(_) { Inline } else { Direct }
}

///|
/// A key, bare or quoted, possibly dotted.
fn Reader::path(self : Reader) -> Array[String] raise Refused {
  let out : Array[String] = []
  for ;; {
    self.gap()
    out.push(self.key())
    self.gap()
    if self.cur() == 0x2e {
      self.bump()
      continue
    }
    break
  }
  out
}

///|
/// One key segment.
fn Reader::key(self : Reader) -> String raise Refused {
  match self.cur() {
    0x22 => self.basic()
    0x27 => self.literal()
    _ => {
      let start = self.pos
      while !self.eof() {
        let c = self.cur()
        let bare = (c >= 0x41 && c <= 0x5a) ||
          (c >= 0x61 && c <= 0x7a) ||
          (c >= 0x30 && c <= 0x39) ||
          c == 0x5f ||
          c == 0x2d
        if !bare {
          break
        }
        self.bump()
      }
      if self.pos == start {
        raise Unexpected(self.at(), self.printable())
      }
      self.src[start:self.pos].to_owned()
    }
  }
}

///|
/// The dotted form of a path, for an error message and for the `seen` table.
fn join(path : Array[String]) -> String {
  let out = StringBuilder()
  for i = 0; i < path.length(); i = i + 1 {
    if i > 0 {
      out.write_char('.')
    }
    out.write_string(path[i])
  }
  out.to_string()
}

// -- values -------------------------------------------------------------------

///|
/// A value of any kind.
fn Reader::value(self : Reader, depth : Int32) -> Json raise Refused {
  if depth > self.flavor.depth {
    raise TooDeep(self.at())
  }
  match self.cur() {
    0x22 =>
      if self.ahead(1) == 0x22 && self.ahead(2) == 0x22 {
        Json::string(self.multiline_basic())
      } else {
        Json::string(self.basic())
      }
    0x27 =>
      if self.ahead(1) == 0x27 && self.ahead(2) == 0x27 {
        Json::string(self.multiline_literal())
      } else {
        Json::string(self.literal())
      }
    0x5b => self.array(depth)
    0x7b => self.inline(depth)
    _ => self.scalar()
  }
}

///|
/// An array, which may span lines and may end with a comma (§Array).
fn Reader::array(self : Reader, depth : Int32) -> Json raise Refused {
  let at = self.at()
  self.bump()
  let out : Array[Json] = []
  for ;; {
    self.skip()
    if self.eof() {
      raise Truncated(at)
    }
    if self.cur() == 0x5d {
      self.bump()
      break
    }
    out.push(self.value(depth + 1))
    self.skip()
    if self.cur() == 0x2c {
      self.bump()
    } else if self.cur() != 0x5d {
      raise Unexpected(self.at(), self.printable())
    }
  }
  Json::array(out)
}

///|
/// An inline table (§Inline Table).
///
/// It is closed the moment its brace closes: §Inline Table says a key may not be
/// added to it afterwards, which is why it is marked `Inline` rather than `Direct`.
/// TOML 1.0.0 also keeps it on one line and forbids a trailing comma, both of which
/// are refused here rather than tolerated.
fn Reader::inline(self : Reader, depth : Int32) -> Json raise Refused {
  let at = self.at()
  self.bump()
  let fields : Map[String, Json] = Map([])
  self.gap()
  if self.cur() == 0x7d {
    self.bump()
    return Json::object(fields)
  }
  for ;; {
    self.gap()
    let kat = self.at()
    let path = self.path()
    self.gap()
    if self.cur() != 0x3d {
      raise Unexpected(self.at(), self.printable())
    }
    self.bump()
    self.gap()
    let value = self.value(depth + 1)
    let mut table = fields
    for i = 0; i < path.length() - 1; i = i + 1 {
      let name = path[i]
      match table.get(name) {
        Some(Object(inner)) => table = inner
        Some(_) => raise Redefined(kat, name)
        None => {
          let fresh : Map[String, Json] = Map([])
          table[name] = Json::object(fresh)
          table = fresh
        }
      }
    }
    let name = path[path.length() - 1]
    if table.get(name) is Some(_) {
      raise Redefined(kat, name)
    }
    table[name] = value
    self.gap()
    if self.cur() == 0x2c {
      self.bump()
      self.gap()
      // A trailing comma is not allowed in 1.0.0.
      if self.cur() == 0x7d {
        raise Unexpected(self.at(), '}')
      }
      continue
    }
    if self.cur() == 0x7d {
      self.bump()
      break
    }
    if self.eof() {
      raise Truncated(at)
    }
    raise Unexpected(self.at(), self.printable())
  }
  Json::object(fields)
}

///|
/// A bare value: a boolean, a date-time, or a number.
fn Reader::scalar(self : Reader) -> Json raise Refused {
  let at = self.at()
  let start = self.pos
  while !self.eof() {
    let c = self.cur()
    if c == 0x0a ||
      c == 0x0d ||
      c == 0x2c ||
      c == 0x5d ||
      c == 0x7d ||
      c == 0x23 {
      break
    }
    // A space ends a value unless it is the one joining a date to a time.
    if c == 0x20 || c == 0x09 {
      if !self.looks_like_time(self.pos + 1) {
        break
      }
    }
    self.bump()
  }
  let text = trim(self.src[start:self.pos].to_owned())
  if text.length() == 0 {
    raise Unexpected(at, self.printable())
  }
  match text {
    "true" => return Json::boolean(true)
    "false" => return Json::boolean(false)
    _ => ()
  }
  // A date-time is the one kind TOML gives a type of its own, so it is read as
  // one and normalised; everything else numeric is a number.
  if dateish(text) {
    let m = @moondate.parse(text[:]) catch { _ => raise BadDate(at) }
    return Json::string(m.to_string())
  }
  number(text, at)
}

///|
/// Whether the run at `from` begins `HH:MM`, which is the only thing that may
/// follow the space inside a date-time.
fn Reader::looks_like_time(self : Reader, from : Int32) -> Bool {
  if from + 5 > self.src.length() {
    return false
  }
  let d = fn(i : Int32) -> Bool {
    let c = self.src[i].to_int()
    c >= 0x30 && c <= 0x39
  }
  d(from) && d(from + 1) && self.src[from + 2].to_int() == 0x3a
}

///|
/// Whether text looks like one of TOML's four date-time forms rather than a number.
///
/// A date has a dash after four digits; a time has a colon after two. Neither
/// shape can be a number, so the test is exact rather than a guess.
fn dateish(s : String) -> Bool {
  if s.length() >= 5 && s[2].to_int() == 0x3a {
    return true
  }
  s.length() >= 10 && s[4].to_int() == 0x2d && s[7].to_int() == 0x2d
}

///|
/// A number in any of the four bases TOML writes, or a float.
fn number(text : String, at : At) -> Json raise Refused {
  // Underscores group digits and mean nothing else (§Integer).
  let bare = strip_underscores(text, at)
  if bare.length() == 0 {
    raise BadNumber(at)
  }
  let (sign, body) = if bare[0].to_int() == 0x2d {
    (-1.0, bare[1:].to_owned())
  } else if bare[0].to_int() == 0x2b {
    (1.0, bare[1:].to_owned())
  } else {
    (1.0, bare)
  }
  match body {
    "inf" => return Json::number(sign * @double.infinity)
    "nan" => return Json::number(@double.not_a_number)
    _ => ()
  }
  if body.length() > 2 && body[0].to_int() == 0x30 {
    let radix = match body[1].to_int() {
      0x78 => 16
      0x6f => 8
      0x62 => 2
      _ => 0
    }
    if radix != 0 {
      let mut acc = 0.0
      for i = 2; i < body.length(); i = i + 1 {
        guard nibble(body[i].to_int()) is Some(d) else { raise BadNumber(at) }
        if d >= radix {
          raise BadNumber(at)
        }
        acc = acc * radix.to_double() + d.to_double()
      }
      // No `repr`: `0xDEADBEEF` is not a JSON number, and the tree this builds
      // has to stay one.
      return Json::number(sign * acc)
    }
  }
  // A leading zero is only legal on its own (§Integer), which is what stops
  // `0123` from being read as 123 or as octal.
  if body.length() > 1 &&
    body[0].to_int() == 0x30 &&
    body[1].to_int() >= 0x30 &&
    body[1].to_int() <= 0x39 {
    raise BadNumber(at)
  }
  match decimal(body) {
    // The text is kept when it is itself a JSON number, so a value past what a
    // Double holds exactly writes back as the digits it was read from. A `+`, an
    // underscore or another base is not, so those carry no text and are written
    // from the value.
    Some(v) =>
      if json_number(text) {
        Json::number(sign * v, repr=text)
      } else {
        Json::number(sign * v)
      }
    None => raise BadNumber(at)
  }
}

///|
/// A decimal integer or float, with an optional exponent.
fn decimal(s : String) -> Double? {
  let mut i = 0
  let mut whole = 0.0
  let mut digits = false
  while i < s.length() && s[i].to_int() >= 0x30 && s[i].to_int() <= 0x39 {
    whole = whole * 10.0 + (s[i].to_int() - 0x30).to_double()
    digits = true
    i = i + 1
  }
  let mut value = whole
  if i < s.length() && s[i].to_int() == 0x2e {
    i = i + 1
    let mut frac = 0.0
    let mut scale = 1.0
    let mut any = false
    while i < s.length() && s[i].to_int() >= 0x30 && s[i].to_int() <= 0x39 {
      frac = frac * 10.0 + (s[i].to_int() - 0x30).to_double()
      scale = scale * 10.0
      any = true
      i = i + 1
    }
    // TOML requires a digit either side of the dot.
    if !any || !digits {
      return None
    }
    value = value + frac / scale
  }
  if !digits {
    return None
  }
  if i < s.length() && (s[i].to_int() == 0x65 || s[i].to_int() == 0x45) {
    i = i + 1
    let mut esign = 1
    if i < s.length() && (s[i].to_int() == 0x2b || s[i].to_int() == 0x2d) {
      if s[i].to_int() == 0x2d {
        esign = -1
      }
      i = i + 1
    }
    let mut exp = 0
    let mut any = false
    while i < s.length() && s[i].to_int() >= 0x30 && s[i].to_int() <= 0x39 {
      exp = exp * 10 + (s[i].to_int() - 0x30)
      any = true
      i = i + 1
    }
    if !any {
      return None
    }
    let mut factor = 1.0
    for k = 0; k < exp; k = k + 1 {
      factor = factor * 10.0
    }
    value = if esign < 0 { value / factor } else { value * factor }
  }
  if i != s.length() {
    return None
  }
  Some(value)
}

///|
/// The text with its digit-grouping underscores removed.
///
/// An underscore must sit between two digits, so a leading, trailing or doubled one
/// is a fault rather than decoration.
fn strip_underscores(s : String, at : At) -> String raise Refused {
  if index_of(s, 0x5f) < 0 {
    return s
  }
  let out = StringBuilder()
  for i = 0; i < s.length(); i = i + 1 {
    if s[i].to_int() != 0x5f {
      out.write_char(s[i].unsafe_to_char())
      continue
    }
    if i == 0 || i + 1 >= s.length() {
      raise BadNumber(at)
    }
    if !is_alnum(s[i - 1].to_int()) || !is_alnum(s[i + 1].to_int()) {
      raise BadNumber(at)
    }
  }
  out.to_string()
}

///|
fn is_alnum(c : Int32) -> Bool {
  (c >= 0x30 && c <= 0x39) ||
  (c >= 0x41 && c <= 0x46) ||
  (c >= 0x61 && c <= 0x66)
}

///|
fn nibble(c : Int32) -> Int32? {
  if c >= 0x30 && c <= 0x39 {
    Some(c - 0x30)
  } else if c >= 0x61 && c <= 0x66 {
    Some(c - 0x61 + 10)
  } else if c >= 0x41 && c <= 0x46 {
    Some(c - 0x41 + 10)
  } else {
    None
  }
}

///|
fn index_of(s : String, u : Int32) -> Int32 {
  for i = 0; i < s.length(); i = i + 1 {
    if s[i].to_int() == u {
      return i
    }
  }
  -1
}

///|
fn trim(s : String) -> String {
  let mut a = 0
  let mut b = s.length()
  while a < b && (s[a].to_int() == 0x20 || s[a].to_int() == 0x09) {
    a = a + 1
  }
  while b > a && (s[b - 1].to_int() == 0x20 || s[b - 1].to_int() == 0x09) {
    b = b - 1
  }
  s[a:b].to_owned()
}

// -- strings ------------------------------------------------------------------

///|
/// A basic string `"…"`, which carries escapes.
fn Reader::basic(self : Reader) -> String raise Refused {
  let at = self.at()
  self.bump()
  let out = StringBuilder()
  for ;; {
    if self.eof() || self.cur() == 0x0a {
      raise Truncated(at)
    }
    let c = self.cur()
    if c == 0x22 {
      self.bump()
      break
    }
    if c == 0x5c {
      self.escape(out)
      continue
    }
    out.write_char(self.src[self.pos].unsafe_to_char())
    self.bump()
  }
  out.to_string()
}

///|
/// A literal string `'…'`, which carries none — which is why a Windows path goes
/// in one.
fn Reader::literal(self : Reader) -> String raise Refused {
  let at = self.at()
  self.bump()
  let start = self.pos
  for ;; {
    if self.eof() || self.cur() == 0x0a {
      raise Truncated(at)
    }
    if self.cur() == 0x27 {
      break
    }
    self.bump()
  }
  let text = self.src[start:self.pos].to_owned()
  self.bump()
  text
}

///|
/// A multi-line basic string `"""…"""`.
fn Reader::multiline_basic(self : Reader) -> String raise Refused {
  let at = self.at()
  for i = 0; i < 3; i = i + 1 {
    self.bump()
  }
  // A newline immediately after the opening delimiter is not part of the value.
  if self.cur() == 0x0d {
    self.bump()
  }
  if self.cur() == 0x0a {
    self.bump()
  }
  let out = StringBuilder()
  for ;; {
    if self.eof() {
      raise Truncated(at)
    }
    if self.cur() == 0x22 && self.ahead(1) == 0x22 && self.ahead(2) == 0x22 {
      for i = 0; i < 3; i = i + 1 {
        self.bump()
      }
      // Up to two more quotes belong to the value, so `""""""` is two quotes.
      let mut extra = 0
      while self.cur() == 0x22 && extra < 2 {
        out.write_char('"')
        self.bump()
        extra = extra + 1
      }
      break
    }
    if self.cur() == 0x5c {
      // A backslash at the end of a line eats the break and the whitespace after
      // it, which is how a long line is written without one.
      let save = self.pos
      self.bump()
      self.gap()
      if self.cur() == 0x0a || self.cur() == 0x0d {
        while self.cur() == 0x20 ||
              self.cur() == 0x09 ||
              self.cur() == 0x0a ||
              self.cur() == 0x0d {
          self.bump()
        }
        continue
      }
      self.pos = save
      self.escape(out)
      continue
    }
    if self.cur() == 0x0d {
      self.bump()
      continue
    }
    out.write_char(self.src[self.pos].unsafe_to_char())
    self.bump()
  }
  out.to_string()
}

///|
/// A multi-line literal string `'''…'''`.
fn Reader::multiline_literal(self : Reader) -> String raise Refused {
  let at = self.at()
  for i = 0; i < 3; i = i + 1 {
    self.bump()
  }
  if self.cur() == 0x0d {
    self.bump()
  }
  if self.cur() == 0x0a {
    self.bump()
  }
  let out = StringBuilder()
  for ;; {
    if self.eof() {
      raise Truncated(at)
    }
    if self.cur() == 0x27 && self.ahead(1) == 0x27 && self.ahead(2) == 0x27 {
      for i = 0; i < 3; i = i + 1 {
        self.bump()
      }
      let mut extra = 0
      while self.cur() == 0x27 && extra < 2 {
        out.write_char('\'')
        self.bump()
        extra = extra + 1
      }
      break
    }
    if self.cur() == 0x0d {
      self.bump()
      continue
    }
    out.write_char(self.src[self.pos].unsafe_to_char())
    self.bump()
  }
  out.to_string()
}

///|
/// One escape past the backslash (§String).
fn Reader::escape(self : Reader, out : StringBuilder) -> Unit raise Refused {
  let at = self.at()
  self.bump()
  let e = self.cur()
  self.bump()
  match e {
    0x62 => out.write_char('\u{08}')
    0x74 => out.write_char('\t')
    0x6e => out.write_char('\n')
    0x66 => out.write_char('\u{0c}')
    0x72 => out.write_char('\r')
    0x22 => out.write_char('"')
    0x5c => out.write_char('\\')
    0x75 => self.hex(out, 4, at)
    0x55 => self.hex(out, 8, at)
    _ => raise BadEscape(at)
  }
}

///|
fn Reader::hex(
  self : Reader,
  out : StringBuilder,
  n : Int32,
  at : At,
) -> Unit raise Refused {
  let mut v = 0
  for i = 0; i < n; i = i + 1 {
    guard nibble(self.cur()) is Some(d) else { raise BadEscape(at) }
    v = (v << 4) | d
    self.bump()
  }
  if v > 0x10ffff || (v >= 0xd800 && v <= 0xdfff) {
    raise BadEscape(at)
  }
  out.write_char(v.unsafe_to_char())
}

///|
/// Whether `s` is spelled the way JSON spells a number (RFC 8259 §6).
///
/// TOML writes several that JSON does not — a leading `+`, underscores between
/// digits, hexadecimal, `inf` — and the tree this module builds is a JSON tree, so
/// only a spelling JSON shares may be carried through as text.
fn json_number(s : String) -> Bool {
  let mut i = 0
  if i < s.length() && s[i].to_int() == 0x2d {
    i = i + 1
  }
  let start = i
  while i < s.length() && s[i].to_int() >= 0x30 && s[i].to_int() <= 0x39 {
    i = i + 1
  }
  if i == start {
    return false
  }
  // JSON allows no leading zero on a multi-digit integer part.
  if i - start > 1 && s[start].to_int() == 0x30 {
    return false
  }
  if i < s.length() && s[i].to_int() == 0x2e {
    i = i + 1
    let frac = i
    while i < s.length() && s[i].to_int() >= 0x30 && s[i].to_int() <= 0x39 {
      i = i + 1
    }
    if i == frac {
      return false
    }
  }
  if i < s.length() && (s[i].to_int() == 0x65 || s[i].to_int() == 0x45) {
    i = i + 1
    if i < s.length() && (s[i].to_int() == 0x2b || s[i].to_int() == 0x2d) {
      i = i + 1
    }
    let exp = i
    while i < s.length() && s[i].to_int() >= 0x30 && s[i].to_int() <= 0x39 {
      i = i + 1
    }
    if i == exp {
      return false
    }
  }
  i == s.length()
}
