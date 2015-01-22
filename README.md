# etcd-tcl

etcd-tcl is an implementation of the [etcd][1] [API][2] v. 2 in Tcl.
The library originates from [biot][3], but was forked out since there
was no etcd client implementation for Tcl.  It provides for a nearly
complete implementation of the API.  etcd-tcl is self-contained and
comes with its own JSON parser, a fork of the excellent parser that is
[part of jimhttp][4].

  [1]: https://github.com/coreos/etcd
  [2]: https://coreos.com/docs/distributed-configuration/etcd-api/
  [3]: https://bitbucket.org/enbygg3/biot
  [4]: https://github.com/dbohdan/jimhttp/blob/master/json.tcl


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

### Key Operations

#### Write a Key

The following would create (or update) the key `/onedir/onekey` to the
string `hello the world`.  If existent, the procedure returns the
previous content of the key.

    ::etcd::write $cx "/onedir/onekey" "hello the world"

To write a key and associate a ttl to it, call it as follows:

    ::etcd::write $cx "/onedir/onekey" "Short lived value" ttl 5

#### Read a Key

The following would read back the content of the key:

    set val [::etcd::read $cx "/onedir/onekey"]

#### Delete a Key

To delete a single key (but not a directory), call `::etcd::delete` as
follows:

    ::etcd::delete $cx "/onedir/onekey"

### Directory Operations

#### Create a Directory

To create a directory do something similar to the following example:

    ::etcd::mkdir $cx "/onedir/subdir"

#### List directory Content

Assuming you have run the example command from just above, we start by
(re)creating a key in the directory, just to make this a better
example:

    ::etcd::write $cx "/onedir/onekey" "hello"

##### Simple Listing

To list the content of a directory, use the following:

    set content [::etcd::glob $cx "/onedir"]

`content` would then contain a representation of the directory and its
direct content where entries are desribed in triplets:

1. The first item contains the full path to the directory entry.
2. The second item contains a boolean: 1 if the entry is a directory
   itself, 0 if the entry is a key instead.
3. The third item contains the value of the key if the entry was a key
   (or an empty string if the entry was a directory).

In other words, in our example, `content` would be set to the following:

    /onedir 1 {} /onedir/subdir 1 {} /onedir/onekey 0 hello

##### Recursion

To recurse through directories, just add a boolean requesting for
recursion to the call, e.g.

    set content [::etcd::glob $cx "/" 1]

##### Globbing

Finally, the procedure is called `glob`, so it also accepts a matching
pattern to select only entries which names match.  So for example, the
command below

    set content [::etcd::glob $cx "/onedir" 0 "sub*"]

would return a single triplet, since there is only one entry which
name matches `sub*` in the directory, e.g.:

    /onedir/subdir 1 {}

#### Remove a Directory

To remove an empty directory, do as follows:

    ::etcd::rmdir $cx "/onedir/subdir"

And to remote a directory recursively, i.e. the whole tree starting at
that directory, call it as follows:

    ::etcd::rmdir $cx "/onedir" 1

### Cluster Information

The following two self-explanatory examples would respectively return
the URL to the leader of the cluster and list of machines bound to the
cluster:

    set leader [::etcd::leader $cx]
    set machines [::etcd::machines $cx]


## Advanced Usage

The procedures `::etcd::read`, `::etcd::write` and `::etcd::delete`
takes more arguments than the ones that have been covered in the
previous section.  In fact, they take any number of arguments, and
this unbound argument list carries both options to modify the
behaviour of the procedure, but also arguments that will be sent to
the remote `etcd` server as part of the HTTP query.  How the
difference between options and API arguments is made is described
below.

Everything that comes prior to the double-dash sign, i.e. `--`
consists of a number of dash-led options, with or without values.
These options are meant to change the behaviour of the procedure.
Everything that comes after `--` forms a list of arguments and values
that will form the HTTP query of the API call to the remote `etcd`
server.

The `--` is optional, in which case, options will be parsed and
removed from the whole list and what remains will be the arguments and
values to be sent to the remote `etcd` server.  In that case, you may
encounter problems if one of the arguments or values starts with a
dash and could be understood as a procedure option instead.

All three procedures takes an option called `-raw`, which does not
take any argument.  This option will prevent the procedure to attempt
JSON parsing the response from `etcd`, returning the raw data directly
instead.  In addition, `::etcd::write` takes an option called
`-ignore` (or `-noval`, they are synonyms) that will not send the
value.  This is meant to be used for directory creation.

### Simple Example

Given these options and mechanisms, and with knowledge of the [etcd
API Documentation][2], instead of calling `::etcd::rmdir`, you could
call `::etcd::delete` as follows:

    ::etcd::delete $cx /onedir/subdir -raw dir true

In fact this is exactly how the implementation of `::etcd::rmdir`
looks like!

### Advanced etcd API

Based on these low-level behaviours, benefiting from the atomic
compare and swap features of `etcd` is examplified below:

    # Set value of /onedir/akey to 10 only if it was 0 before:
    ::etcd::write /onedir/akey 10 prevValue 0

    # Set value of /onedir/akey to 10 only if it did not exist before
    ::etcd::write /onedir/akey 10 prevExists false

    # Set value of /onedir/akey to 10 only if it was at version 102
    ::etcd::write /onedir/akey 10 prevIndex 102


