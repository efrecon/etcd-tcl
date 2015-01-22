# etcd-tcl

etcd-tcl is an implementation of the etcd[1] API[2] v. 2 in Tcl.  The
library provides for a nearly complete implementation of the API.
etcd-tcl is self-contained and comes with its own JSON parser, a fork
of the excellent parser that is [part of jimhttp][3].

  [1]: https://github.com/coreos/etcd
  [2]: https://coreos.com/docs/distributed-configuration/etcd-api/
  [3]: https://github.com/dbohdan/jimhttp/blob/master/json.tcl


# Installation

Make sure you can access the directory called `etcd` so as to `package
require` it. That's it.

# Usage

All commands live in the `etcd` namespace.  In order to start
interacting with a remote `etcd` server, you will have to create a
connection context using `::etcd::new`, the procedure returns a token
that is to be used in all further calls when interacting with that
`etcd` instance.  You can have as many tokens as necessary.

The API provides naming conventions that should be familiar to most
Tcl'ers.  `::etcd::read`, `::etcd::write` and `::etcd::delete` to
read, write and delete keys, `::etcd::mkdir` and `::etcd::rmdir` to
create directories, etc.  In fact, under the hood, most of the work is
being done by `::etcd::read`, `::etcd::write` and `::etcd::delete`,
while other procedures relay those procedures with specific arguments.
This is because the three procedure provide for a flexible calling
convention that both allows for a simpler usage and open for more
complex scenarios.

## Simple Usage

### Create Connection Context

Create a connection context as examplified below.

    set cx [::etcd::new -host localhost -port 4001]

`localhost` and `4001` are the defaults for the `-host` and `-port`
options, so this could actually be shortened to `set cx
[::etcd::new]`...

All the following examples supposes that the variable `cx` holds a
token that has been returned by `::etcd::new`.

### Write a key

The following would create (or update) the key `/onedir/onekey` to the
string `hello the world`.  If existent, the procedure returns the
previous content of the key.

    ::etcd::write $cx "/onedir/onekey" "hello the world"

To write a key and associate a ttl to it, call it as follows:

    ::etcd::write $cx "/onedir/onekey" "Short lived value" ttl 5


