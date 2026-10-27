// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// A fuller integration: a small site config is read, inspected, changed and
// written back, then a broken config is reported by the line it failed on.
//
// It uses tables, an array of tables, dotted keys, a date, a hexadecimal
// integer and a byte-order mark, which is most of what a real config file holds.
//
// Run it with `moon run examples/integration`.

///|
/// The parts of the config this program actually consumes.
struct Site {
  title : String
  port : Int32
  host : String
  tls : Bool
  routes : Array[String]
}

///|
fn main raise {
  let src =
    #|title = "field notes"
    #|port = 0x1F90
    #|started = 2026-03-01 09:30:00Z
    #|
    #|[server]
    #|host = "127.0.0.1"
    #|tls = false
    #|limits.timeout = 30
    #|
    #|[[route]]
    #|path = "/"
    #|methods = [ "GET" ]
    #|
    #|[[route]]
    #|path = "/notes"
    #|methods = [ "GET", "POST" ]
    #|

  // Read the document once, then take what the program needs out of the tree.
  let doc = @moontoml.loads(src[:])
  guard doc is Object(root) else { abort("a document is a table") }
  let site = read(root)

  println("\{site.title} on \{site.host}:\{site.port}")
  println("tls = \{site.tls}, routes = \{site.routes.length()}")
  for route in site.routes {
    println("  \{route}")
  }

  // Change the tree the way the program would, then write it as sorted TOML so
  // the output has one order no matter how the input was laid out.
  match root.get("server") {
    Some(Object(server)) => server["tls"] = Json::boolean(true)
    _ => ()
  }
  let route : Map[String, Json] = {
    "path": Json::string("/about"),
    "methods": Json::array([Json::string("GET")]),
  }
  match root.get("route") {
    Some(Array(items)) => items.push(Json::object(route))
    _ => root["route"] = Json::array([Json::object(route)])
  }
  println("")
  println(@moontoml.dumps(doc, sort=true))

  // A refused document says where it stopped, so the caller can point at it.
  let broken = "port = 1\nport = 2\n"
  let refusal = try {
    let _ = @moontoml.loads(broken[:])
    None
  } catch {
    e => Some(e)
  }
  match refusal {
    Some(e) =>
      println("refused at line \{e.at().line}, column \{e.at().column}: \{e}")
    None => println("no refusal")
  }
}

///|
/// Pull the fields the program uses out of the root table.
fn read(root : Map[String, Json]) -> Site {
  let title = match root.get("title") {
    Some(String(s)) => s
    _ => "?"
  }
  let port = match root.get("port") {
    Some(Number(n, ..)) => n.to_int()
    _ => 0
  }
  // A sub-table is just a `Json` object under a key.
  let (host, tls) = match root.get("server") {
    Some(Object(server)) =>
      (
        match server.get("host") {
          Some(String(s)) => s
          _ => "localhost"
        },
        match server.get("tls") {
          Some(True) => true
          _ => false
        },
      )
    _ => ("localhost", false)
  }
  // An array of tables is an array whose elements are objects.
  let routes = match root.get("route") {
    Some(Array(items)) =>
      items
      .iter()
      .filter_map(fn(item) {
        match item {
          Object(r) =>
            match r.get("path") {
              Some(String(p)) => Some(p)
              _ => None
            }
          _ => None
        }
      })
      .collect()
    _ => []
  }
  { title, port, host, tls, routes, }
}
