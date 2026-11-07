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
  // A value took the path, or a dotted key made a table there.
  Taken
  Header
  Inline
  Tables
}

///|
/// The kind of thing an item of a document is.
#derive(Debug)
pub(all) enum ItemKind {
  Header
  Pair
}

///|
pub extend ItemKind with Debug::{to_repr}

///|
/// One thing a document holds, in the order it was read: a table header or a
/// key-value pair.
///
/// The four offsets say where the line and, for a pair, its value sat in the
/// source. The document tiles exactly as the run of its items and the text
/// between them, so writing it back over the source is the original byte for byte
/// unless a pair's value has moved, in which case only that value is written fresh
/// and the key, the separator and any trailing comment are kept as they were.
#derive(Debug)
pub(all) struct Item {
  kind : ItemKind
  // The key's full path from the root, including the table a header opens.
  path : Array[String]
  // Where the line began.
  start : Int32
  // For a pair, where its value began and where it ended.
  vstart : Int32
  vend : Int32
  // Where the line ended — before its trailing line break.
  end : Int32
  // Whether the value has been changed since the document was read.
  mut changed : Bool
}

///|
pub extend Item with Debug::{to_repr}

///|
/// A header item, which holds no value of its own.
fn Item::header(path : Array[String], start : Int32, end : Int32) -> Item {
  { kind: Header, path, start, vstart: 0, vend: 0, end, changed: false, }
}

///|
/// A pair item, whose value ran from `vstart` to `vend`.
fn Item::pair(
  path : Array[String],
  start : Int32,
  vstart : Int32,
  vend : Int32,
  end : Int32,
) -> Item {
  { kind: Pair, path, start, vstart, vend, end, changed: false, }
}

///|
/// The grammar an edition admits, as the gates the reader checks against.
///
/// The editions grow the format by real features, and a document that uses one
/// before it exists is refused: `v04` has no dotted keys, no hex/octal/binary
/// integers, no `inf`/`nan` and only the offset date-time; `v05` adds those four;
/// `v100` allows a mixed-type array; and `v110` relaxes an inline table to span
/// lines with a trailing comma, adds the `\x` and `\e` escapes and lets a time
/// drop its seconds.
priv struct Caps {
  // A key may carry more than one segment.
  dotted : Bool
  // An integer may carry a 0x, 0o or 0b prefix.
  prefixed : Bool
  // A float may be `inf` or `nan`.
  inf_nan : Bool
  // A date-time may be local — a bare date, a bare time, or a date-time with no
  // offset — rather than only the offset form that 0.4 knows.
  local_dt : Bool
  // An array may hold values of more than one kind.
  mixed : Bool
  // An inline table may span lines and end with a comma.
  multi_inline : Bool
  // A basic string may use the \x escape for the first 255 code points.
  x_esc : Bool
  // A basic string may use the \e escape.
  e_esc : Bool
  // A time may drop its seconds.
  opt_secs : Bool
}

///|
fn caps_of(edition : Edition) -> Caps {
  match edition {
    V04 =>
      {
        dotted: false,
        prefixed: false,
        inf_nan: false,
        local_dt: false,
        mixed: false,
        multi_inline: false,
        x_esc: false,
        e_esc: false,
        opt_secs: false,
      }
    V05 =>
      {
        dotted: true,
        prefixed: true,
        inf_nan: true,
        local_dt: true,
        mixed: false,
        multi_inline: false,
        x_esc: false,
        e_esc: false,
        opt_secs: false,
      }
    V100 =>
      {
        dotted: true,
        prefixed: true,
        inf_nan: true,
        local_dt: true,
        mixed: true,
        multi_inline: false,
        x_esc: false,
        e_esc: false,
        opt_secs: false,
      }
    V110 =>
      {
        dotted: true,
        prefixed: true,
        inf_nan: true,
        local_dt: true,
        mixed: true,
        multi_inline: true,
        x_esc: true,
        e_esc: true,
        opt_secs: true,
      }
  }
}

///|
/// Where the reader is and what it has built.
priv struct Reader {
  src : StringView
  mut pos : Int32
  mut line : Int32
  mut bol : Int32
  flavor : Flavor
  caps : Caps
  root : Map[String, Value]
  // The table that bare keys land in, and the path its header named.
  mut here : Map[String, Value]
  mut prefix : Array[String]
  // How each dotted path came to exist.
  seen : Map[String, Kind]
  // When the document is also kept as a `Document`, each item is recorded with the
  // exact span it occupied; writing the items back over the source reproduces it
  // byte for byte, and only a replaced value is written fresh.
  mut recording : Bool
  rec_items : Array[Item]
}

///|
fn Reader::new(src : StringView, flavor : Flavor) -> Reader {
  let root : Map[String, Value] = Map([])
  {
    src,
    pos: 0,
    line: 1,
    bol: 0,
    flavor,
    caps: caps_of(flavor.edition),
    root,
    here: root,
    prefix: [],
    seen: Map([]),
    recording: false,
    rec_items: [],
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

///|
/// The key's full path from the root, which is what a pair lands in.
fn Reader::full_path(self : Reader, path : Array[String]) -> Array[String] {
  let out : Array[String] = []
  for name in self.prefix {
    out.push(name)
  }
  for name in path {
    out.push(name)
  }
  out
}

// -- the document -------------------------------------------------------------

///|
/// The whole document: a run of key-value pairs and table headers.
fn Reader::document(self : Reader) -> Value raise Refused {
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
  Value::Table(self.root)
}

///|
/// A `[table]` or `[[array of tables]]` header (§Table, §Array of Tables).
fn Reader::header(self : Reader) -> Unit raise Refused {
  let at = self.at()
  let start = self.pos
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
  let end = self.pos
  self.end_of_line()
  if self.recording {
    self.rec_items.push(Item::header(self.full_path(path), start, end))
  }
  self.here = if array {
    self.open_tables(path, at)
  } else {
    self.open_table(path, at)
  }
  self.prefix = path
}

///|
/// Walk to the table `path` names, creating what is missing, and mark it opened.
fn Reader::open_table(
  self : Reader,
  path : Array[String],
  at : At,
) -> Map[String, Value] raise Refused {
  let full = join(path)
  // A header may not repeat, and may not open something a dotted key already made,
  // a value already took, an array of tables already holds, or an inline table
  // closed.
  match self.seen.get(path_key(path)) {
    Some(_) => raise Redefined(at, full)
    None => ()
  }
  let table = self.walk(path, at)
  self.seen[path_key(path)] = Header
  table
}

///|
/// The same for `[[…]]`, which appends a table to an array rather than opening one.
fn Reader::open_tables(
  self : Reader,
  path : Array[String],
  at : At,
) -> Map[String, Value] raise Refused {
  let parent = self.walk(path[0:path.length() - 1].to_owned(), at)
  let name = path[path.length() - 1]
  let full = join(path)
  match self.seen.get(path_key(path)) {
    Some(Tables) | None => ()
    Some(_) => raise Redefined(at, full)
  }
  self.seen[path_key(path)] = Tables
  // A new element is a new namespace: what the element before it defined under the
  // same array is no longer in scope (§Array of Tables).
  let under = path_key(path)
  let defined : Array[String] = []
  for key, _ in self.seen {
    if key.length() > under.length() &&
      key.exact_view(start=0, end=under.length()) == under[:] {
      defined.push(key)
    }
  }
  for key in defined {
    self.seen.remove(key)
  }
  let fresh : Map[String, Value] = Map([])
  match parent.get(name) {
    Some(Array(items)) => {
      items.push(Value::Table(fresh))
      ()
    }
    Some(_) => raise Redefined(at, full)
    None => parent[name] = Value::array([Value::Table(fresh)])
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
) -> Map[String, Value] raise Refused {
  let mut table = self.root
  for i = 0; i < path.length(); i = i + 1 {
    let name = path[i]
    let so_far = path[0:i + 1].to_owned()
    match table.get(name) {
      Some(Table(inner)) => {
        if self.seen.get(path_key(so_far)) is Some(Inline) {
          raise Redefined(at, join(so_far))
        }
        table = inner
      }
      Some(Array(items)) =>
        if self.seen.get(path_key(so_far)) is Some(Tables) && items.length() > 0 {
          match items[items.length() - 1] {
            Table(inner) => table = inner
            _ => raise Redefined(at, join(so_far))
          }
        } else {
          raise Redefined(at, join(so_far))
        }
      Some(_) => raise Redefined(at, join(so_far))
      None => {
        // A table created on the way to somewhere else is implicit and stays
        // unmarked, so its own header may still open it later (§Table).
        let fresh : Map[String, Value] = Map([])
        table[name] = Value::Table(fresh)
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
  let start = self.pos
  let path = self.path()
  self.gap()
  if self.cur() != 0x3d {
    raise Unexpected(self.at(), self.printable())
  }
  self.bump()
  self.gap()
  let vstart = self.pos
  let value = self.value(0)
  let vend = self.pos
  self.end_of_line()
  let end = self.pos
  if self.recording {
    self.rec_items.push(
      Item::pair(self.full_path(path), start, vstart, vend, end),
    )
  }
  // A dotted key walks into tables under the current one; the last segment is the
  // key itself.
  let mut table = self.here
  let walked : Array[String] = []
  for name in self.prefix {
    walked.push(name)
  }
  for i = 0; i < path.length() - 1; i = i + 1 {
    let name = path[i]
    walked.push(name)
    match table.get(name) {
      Some(Table(inner)) => {
        // A dotted key may extend a table it made itself, but not one that a
        // header opened or an inline table closed.
        match self.seen.get(path_key(walked)) {
          Some(Inline) | Some(Header) => raise Redefined(at, join(walked))
          _ => ()
        }
        table = inner
      }
      Some(_) => raise Redefined(at, join(walked))
      None => {
        let fresh : Map[String, Value] = Map([])
        table[name] = Value::Table(fresh)
        self.seen[path_key(walked)] = Taken
        table = fresh
      }
    }
  }
  let name = path[path.length() - 1]
  walked.push(name)
  if table.get(name) is Some(_) {
    raise Redefined(at, join(walked))
  }
  table[name] = value
  self.seen[path_key(walked)] = if value is Table(_) { Inline } else { Taken }
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
      // A dot between two segments is the dotted key; before 0.5 a key is one
      // segment, and a dot inside a quoted key is part of that key, not a dot here.
      if !self.caps.dotted {
        raise Unexpected(self.at(), self.printable())
      }
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
/// A path as one string for the `seen` table, where each segment carries its
/// length.
///
/// Joining with a dot would make `[a.b]` and `[a."b.c"]` the same path, and they
/// are two tables; the lengths make the reading unambiguous whatever a key holds.
fn path_key(path : Array[String]) -> String {
  let out = StringBuilder()
  for name in path {
    out.write_string(name.length().to_string())
    out.write_char(':')
    out.write_string(name)
  }
  out.to_string()
}

///|
/// The dotted form of a path, as a person writes it and as a message shows it.
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
fn Reader::value(self : Reader, depth : Int32) -> Value raise Refused {
  if depth > self.flavor.depth {
    raise TooDeep(self.at())
  }
  match self.cur() {
    0x22 =>
      if self.ahead(1) == 0x22 && self.ahead(2) == 0x22 {
        Value::string(self.multiline_basic())
      } else {
        Value::string(self.basic())
      }
    0x27 =>
      if self.ahead(1) == 0x27 && self.ahead(2) == 0x27 {
        Value::string(self.multiline_literal())
      } else {
        Value::string(self.literal())
      }
    0x5b => self.array(depth)
    0x7b => self.inline(depth)
    _ => self.scalar()
  }
}

///|
/// An array, which may span lines and may end with a comma (§Array).
///
/// 1.0.0 allows an array of mixed kinds; before that an array holds values of one
/// kind only, and a second kind is a fault.
fn Reader::array(self : Reader, depth : Int32) -> Value raise Refused {
  let at = self.at()
  self.bump()
  let out : Array[Value] = []
  // The kind the first element was, which the rest must match until 1.0.
  let mut first : Int32? = None
  for ;; {
    self.skip()
    if self.eof() {
      raise Truncated(at)
    }
    if self.cur() == 0x5d {
      self.bump()
      break
    }
    let held = self.value(depth + 1)
    match first {
      None => first = Some(kind_of(held))
      Some(kind) =>
        if !self.caps.mixed && kind_of(held) != kind {
          raise MixedArray(self.at())
        }
    }
    out.push(held)
    self.skip()
    if self.cur() == 0x2c {
      self.bump()
    } else if self.cur() != 0x5d {
      raise Unexpected(self.at(), self.printable())
    }
  }
  Value::array(out)
}

///|
/// The kind a value is, as a number the array gate compares: an array is mixed
/// the moment two elements differ.
fn kind_of(value : Value) -> Int32 {
  match value {
    String(_) => 0
    Integer(_) => 1
    Float(_) => 2
    Boolean(_) => 3
    Datetime(_) => 4
    Array(_) => 5
    Table(_) => 6
  }
}

///|
/// An inline table (§Inline Table).
///
/// It is closed the moment its brace closes: §Inline Table says a key may not be
/// added to it afterwards, which is why it is marked `Inline` rather than `Direct`.
/// 1.0.0 keeps it on one line and forbids a trailing comma, both refused here; 1.1
/// lets it span lines, carry comments and end with a comma.
fn Reader::inline(self : Reader, depth : Int32) -> Value raise Refused {
  let at = self.at()
  let ml = self.caps.multi_inline
  self.bump()
  let fields : Map[String, Value] = Map([])
  if ml {
    self.skip()
  } else {
    self.gap()
  }
  if self.cur() == 0x7d {
    self.bump()
    return Value::Table(fields)
  }
  // What a dotted key in this brace has made, so a later one may extend it — and
  // one that names a table a value already holds may not.
  let made : Map[String, Bool] = Map([])
  for ;; {
    if ml {
      self.skip()
    } else {
      self.gap()
    }
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
      let here = path[0:i + 1].to_owned()
      match table.get(name) {
        Some(Table(inner)) =>
          if made.get(path_key(here)) is Some(true) {
            table = inner
          } else {
            raise Redefined(kat, join(here))
          }
        Some(_) => raise Redefined(kat, join(here))
        None => {
          let fresh : Map[String, Value] = Map([])
          table[name] = Value::Table(fresh)
          made[path_key(here)] = true
          table = fresh
        }
      }
    }
    let name = path[path.length() - 1]
    if table.get(name) is Some(_) {
      raise Redefined(kat, name)
    }
    table[name] = value
    if ml {
      self.skip()
    } else {
      self.gap()
    }
    if self.cur() == 0x2c {
      self.bump()
      if ml {
        // A trailing comma before the closing brace is allowed from 1.1.
        self.skip()
        if self.cur() == 0x7d {
          self.bump()
          break
        }
        continue
      } else {
        self.gap()
        // A trailing comma is not allowed in 1.0.0.
        if self.cur() == 0x7d {
          raise Unexpected(self.at(), '}')
        }
        continue
      }
    }
    if self.cur() == 0x7d {
      self.bump()
      break
    }
    if self.eof() {
      raise Truncated(at)
    }
    if ml {
      // A key, not a comma, where a comma or a brace is owed.
      raise Unexpected(self.at(), self.printable())
    }
    raise Unexpected(self.at(), self.printable())
  }
  Value::Table(fields)
}

///|
/// A bare value: a boolean, a date-time, or a number.
fn Reader::scalar(self : Reader) -> Value raise Refused {
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
    "true" => return Value::boolean(true)
    "false" => return Value::boolean(false)
    _ => ()
  }
  // A date-time is the one kind TOML gives a type of its own, so it is read as
  // one; everything else bare is a number.
  if dateish(text) {
    if !moment_ok(text, self.caps) {
      raise BadDate(at)
    }
    let m = @moondate.parse(text[:]) catch { _ => raise BadDate(at) }
    return Value::Datetime(m)
  }
  number(text, at, self.caps)
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
/// Whether text is spelled as one of the date-time forms the edition allows.
///
/// The calendar is the date library's business, but the shape is this module's,
/// and it changes with the edition: 0.4 knows only the offset date-time, 0.5 adds
/// the three local kinds and always asks for seconds, and 1.1 lets a time drop its
/// seconds.
fn moment_ok(s : String, caps : Caps) -> Bool {
  let n = s.length()
  let digits = fn(from : Int32, count : Int32) -> Bool {
    if from + count > n {
      return false
    }
    for i = from; i < from + count; i = i + 1 {
      let c = s[i].to_int()
      if c < 0x30 || c > 0x39 {
        return false
      }
    }
    true
  }
  let dash = fn(i : Int32) -> Bool { i < n && s[i].to_int() == 0x2d }
  let colon = fn(i : Int32) -> Bool { i < n && s[i].to_int() == 0x3a }
  // A time on its own, which exists only from 0.5.
  if colon(2) {
    if !caps.local_dt {
      return false
    }
    let end = time_len(s, 0, caps.opt_secs)
    if end < 0 {
      return false
    }
    if end == n {
      return true
    }
    // A fractional second, and nothing after it.
    return s[end].to_int() == 0x2e &&
      fraction_ok(s, end) &&
      fraction_end(s, end) == n
  }
  if !(digits(0, 4) && dash(4) && digits(5, 2) && dash(7) && digits(8, 2)) {
    return false
  }
  if n == 10 {
    // A date on its own, which exists only from 0.5.
    return caps.local_dt
  }
  if n < 11 {
    return false
  }
  let sep = s[10].to_int()
  if sep != 0x54 && sep != 0x74 && sep != 0x20 {
    return false
  }
  let end0 = time_len(s, 11, caps.opt_secs)
  if end0 < 0 {
    return false
  }
  let mut end = end0
  if end < n && s[end].to_int() == 0x2e {
    if !fraction_ok(s, end) {
      return false
    }
    end = fraction_end(s, end)
  }
  if end == n {
    // A local date-time: no offset, allowed only from 0.5.
    return caps.local_dt
  }
  let offset = s[end].to_int()
  if offset == 0x5a || offset == 0x7a {
    return end + 1 == n
  }
  if offset != 0x2b && offset != 0x2d {
    return false
  }
  // `±HH:MM`.
  digits(end + 1, 2) && colon(end + 3) && digits(end + 4, 2) && end + 6 == n
}

///|
/// Where a time at `from` ends — past `HH:MM:SS`, or past `HH:MM` when seconds
/// are optional — or -1 when the text is not a time.
fn time_len(s : String, from : Int32, opt_secs : Bool) -> Int32 {
  let n = s.length()
  let digit = fn(i : Int32) -> Bool {
    if i >= n {
      return false
    }
    let c = s[i].to_int()
    c >= 0x30 && c <= 0x39
  }
  if !(from + 5 <= n &&
    digit(from) &&
    digit(from + 1) &&
    s[from + 2].to_int() == 0x3a &&
    digit(from + 3) &&
    digit(from + 4)) {
    return -1
  }
  let e = from + 5
  if e < n && s[e].to_int() == 0x3a {
    // `:SS` follows.
    if e + 3 > n || !digit(e + 1) || !digit(e + 2) {
      return -1
    }
    e + 3
  } else if opt_secs {
    // `HH:MM`, the seconds dropped.
    e
  } else {
    -1
  }
}

///|
/// Whether a fractional second starts at `from`.
fn fraction_ok(s : String, from : Int32) -> Bool {
  let n = s.length()
  if from >= n || s[from].to_int() != 0x2e {
    return false
  }
  let mut i = from + 1
  while i < n {
    let c = s[i].to_int()
    if c < 0x30 || c > 0x39 {
      break
    }
    i = i + 1
  }
  i > from + 1
}

///|
/// Where the fractional second at `from` ends.
fn fraction_end(s : String, from : Int32) -> Int32 {
  let n = s.length()
  let mut i = from + 1
  while i < n {
    let c = s[i].to_int()
    if c < 0x30 || c > 0x39 {
      break
    }
    i = i + 1
  }
  i
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
///
/// An integer is kept as 64 bits, which is what the format calls it; a float is
/// the nearest double, and keeps the text it was written as so it can be written
/// back the way it came. A prefixed integer and `inf`/`nan` exist only from 0.5,
/// so the edition decides whether they are numbers here.
fn number(text : String, at : At, caps : Caps) -> Value raise Refused {
  let mut at_sign = 0
  let mut negative = false
  if text.length() > 0 {
    let c = text[0].to_int()
    if c == 0x2d || c == 0x2b {
      negative = c == 0x2d
      at_sign = 1
    }
  }
  let body = text[at_sign:].to_owned()
  if body.length() == 0 {
    raise BadNumber(at)
  }
  // TOML writes a prefixed integer with no sign, from 0.5.
  if caps.prefixed && body.length() >= 2 && body[0].to_int() == 0x30 {
    let radix = match body[1].to_int() {
      0x78 => 16
      0x6f => 8
      0x62 => 2
      _ => 0
    }
    if radix != 0 {
      if at_sign == 1 {
        raise BadNumber(at)
      }
      let digits = strip_underscores(body[2:].to_owned(), at, radix)
      if digits.length() == 0 {
        raise BadNumber(at)
      }
      for i = 0; i < digits.length(); i = i + 1 {
        guard nibble(digits[i].to_int()) is Some(d) && d < radix else {
          raise BadNumber(at)
        }
      }
      let whole = @string.parse_int64(digits[:], base=radix) catch {
        _ => raise BadNumber(at)
      }
      return Value::Integer(whole)
    }
  }
  if caps.inf_nan {
    match body {
      "inf" =>
        return Value::Float(
          Real::new(if negative { -@double.infinity } else { @double.infinity }),
        )
      "nan" => return Value::Float(Real::new(@double.not_a_number))
      _ => ()
    }
  }
  let digits = strip_underscores(body, at, 10)
  if digits.length() == 0 {
    raise BadNumber(at)
  }
  if is_float_text(digits) {
    if !float_ok(digits) {
      raise BadNumber(at)
    }
    let value = @string.parse_double(digits[:]) catch {
      // Past the largest double the only honest answer is infinity, which is what
      // the arithmetic says the value is.
      _ => @double.infinity
    }
    let signed = if negative { -value } else { value }
    return Value::Float({
      value: signed,
      // The text is kept only when JSON spells it the same way, because the tree
      // `loads` builds has to carry it as a JSON number.
      repr: if json_number(text) {
        Some(text)
      } else {
        None
      },
    })
  }
  // A leading zero is only legal on its own (§Integer), which is what stops
  // `0123` from being read as 123 or as octal.
  if digits.length() > 1 && digits[0].to_int() == 0x30 {
    raise BadNumber(at)
  }
  for i = 0; i < digits.length(); i = i + 1 {
    let c = digits[i].to_int()
    if c < 0x30 || c > 0x39 {
      raise BadNumber(at)
    }
  }
  let spelled = if negative { "-" + digits } else { digits }
  let whole = @string.parse_int64(spelled[:]) catch { _ => raise BadNumber(at) }
  Value::Integer(whole)
}

///|
/// Whether a run of digits, sign aside, is written as a float.
fn is_float_text(s : String) -> Bool {
  for i = 0; i < s.length(); i = i + 1 {
    let c = s[i].to_int()
    if c == 0x2e || c == 0x65 || c == 0x45 {
      return true
    }
  }
  false
}

///|
/// Whether a float is spelled the way TOML spells one: digits either side of the
/// dot, an exponent with digits, no leading zero on the integer part.
fn float_ok(s : String) -> Bool {
  let n = s.length()
  let digit = fn(i : Int32) -> Bool {
    if i >= n {
      return false
    }
    let c = s[i].to_int()
    c >= 0x30 && c <= 0x39
  }
  let mut i = 0
  while digit(i) {
    i = i + 1
  }
  if i == 0 {
    return false
  }
  if i > 1 && s[0].to_int() == 0x30 {
    return false
  }
  if i < n && s[i].to_int() == 0x2e {
    i = i + 1
    let from = i
    while digit(i) {
      i = i + 1
    }
    if i == from {
      return false
    }
  }
  if i < n && (s[i].to_int() == 0x65 || s[i].to_int() == 0x45) {
    i = i + 1
    if i < n && (s[i].to_int() == 0x2b || s[i].to_int() == 0x2d) {
      i = i + 1
    }
    let from = i
    while digit(i) {
      i = i + 1
    }
    if i == from {
      return false
    }
  }
  i == n
}

///|
/// The text with its digit-grouping underscores removed.
///
/// An underscore groups digits of one base and means nothing else, so one that is
/// not between two digits of that base — leading, trailing, doubled, or next to a
/// dot or an exponent — is a fault rather than decoration.
fn strip_underscores(
  s : String,
  at : At,
  radix : Int32,
) -> String raise Refused {
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
    guard nibble(s[i - 1].to_int()) is Some(before) && before < radix else {
      raise BadNumber(at)
    }
    guard nibble(s[i + 1].to_int()) is Some(after) && after < radix else {
      raise BadNumber(at)
    }
  }
  out.to_string()
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
    // The escapes 1.1 adds, for the two code points a person would otherwise
    // spell long.
    0x65 =>
      if self.caps.e_esc {
        out.write_char('\u{1b}')
      } else {
        raise BadEscape(at)
      }
    0x78 => if self.caps.x_esc { self.x2(out, at) } else { raise BadEscape(at) }
    _ => raise BadEscape(at)
  }
}

///|
/// A two-digit hex escape, `\xHH`, for the first 255 code points.
fn Reader::x2(
  self : Reader,
  out : StringBuilder,
  at : At,
) -> Unit raise Refused {
  guard nibble(self.cur()) is Some(h) else { raise BadEscape(at) }
  let b = h.to_int64() << 4
  self.bump()
  guard nibble(self.cur()) is Some(l) else { raise BadEscape(at) }
  let v = b | l.to_int64()
  self.bump()
  out.write_char(v.to_int().unsafe_to_char())
}

///|
fn Reader::hex(
  self : Reader,
  out : StringBuilder,
  n : Int32,
  at : At,
) -> Unit raise Refused {
  // Eight hex digits do not fit in 32 bits, and `\UFFFFFFFF` is a fault rather
  // than a code point, so the value is gathered wide and checked before it is one.
  let mut v : Int64 = 0
  for i = 0; i < n; i = i + 1 {
    guard nibble(self.cur()) is Some(d) else { raise BadEscape(at) }
    v = (v << 4) | d.to_int64()
    self.bump()
  }
  if v > 0x10ffff || (v >= 0xd800 && v <= 0xdfff) {
    raise BadEscape(at)
  }
  out.write_char(v.to_int().unsafe_to_char())
}

///|
/// Whether `s` is spelled the way JSON spells a number (RFC 8259 §6).
///
/// TOML writes several that JSON does not — a leading `+`, underscores between
/// digits, hexadecimal, `inf` — and the tree `loads` builds is a JSON tree, so
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

///|
/// Refuse a byte that TOML has no place for before anything is read.
///
/// A control character other than tab, line feed and carriage return is not text
/// (§String), and a carriage return is only a line break as half of a CRLF. Taking
/// the pass over the whole document first keeps every reader from repeating it.
fn check_text(src : StringView) -> Unit raise Refused {
  let mut line = 1
  let mut bol = 0
  for i = 0; i < src.length(); i = i + 1 {
    let c = src[i].to_int()
    if c == 0x0a {
      line = line + 1
      bol = i + 1
      continue
    }
    if c == 0x09 || c == 0x0d {
      if c == 0x0d && (i + 1 >= src.length() || src[i + 1].to_int() != 0x0a) {
        raise Unexpected({ at: i, line, column: i - bol + 1, }, '\r')
      }
      continue
    }
    if c < 0x20 || c == 0x7f {
      raise Unexpected(
        { at: i, line, column: i - bol + 1, },
        c.unsafe_to_char(),
      )
    }
  }
}
