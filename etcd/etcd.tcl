##################
## Module Name     --  etcd
## Original Author --  Emmanuel Frecon - emmanuel@sics.se
## Description:
##
##    This library provides an implementation of the etcd API, as
##    described at
##    https://coreos.com/docs/distributed-configuration/etcd-api/.
##    The name of procedures used in this library try to provide for a
##    familiar vocabulary, matching the one of the API
##    documentation. The library is completely safe-contained, coming
##    with its own JSON parser so as to limit dependencies to the
##    strict minimum, i.e. the regular Tcl HTTP package.
##
##################

package require Tcl 8.5;
package require http
package require etcd::json

namespace eval ::etcd {
    variable ETCD
    if {![info exists ETCD]} {
	array set ETCD {
	    idGene         0
	    idClamp        10000
	    idFormat       7
	    version        "v2"
	    verbose        0
	    verboseTags    {1 CRITICAL 2 ERROR 3 WARN 4 NOTICE 5 INFO 6 DEBUG}
	    -host          127.0.0.1
	    -port          4001
	    -proto         http
	    -timeout       30000
	    -keepalive     on
	}
	variable version 0.2
	variable libdir [file dirname [file normalize [info script]]]
    }
    namespace export {[a-z]*}
    namespace ensemble create
}

proc ::etcd::Log { lvl msg } {
    variable ETCD

    if { ![string is integer $lvl] } {
	foreach {l str} [concat $ETCD(verboseTags) 0 *] {
	    if { [string match -nocase $str $lvl] } {
		set lvl $l
		break
	    }
	}
    }
		
    if { $ETCD(verbose) >= $lvl } {
	array set T $ETCD(verboseTags)
	if { [info exists T($lvl)] } {
	    puts stderr "\[$T($lvl)\] $msg"
	}
    }
}


# ::etcd::GetOpt -- Quick and Dirty Options Parser
#
#       Parses options, code comes from wiki
#
# Arguments:
#	_argv	"pointer" to options list to parse from
#	name	Name of option to find
#	_var	"pointer" to where to place the value
#	deflt	Default value if not found
#
# Results:
#       1 if the option was found, 0 otherwise.
#
# Side Effects:
#       Modifies the argv option list.
proc ::etcd::GetOpt {_argv name {_var ""} {deflt ""}} {
    upvar $_argv argv $_var var
    set pos [lsearch -regexp $argv ^$name]
    if {$pos>=0} {
	set to $pos
	if {$_var ne ""} {
	    set var [lindex $argv [incr to]]
	}
	set argv [lreplace $argv $pos $to]
	return 1
    } else {
	# Did we provide a value to default?
	if {[llength [info level 0]] == 5} {set var $deflt}
	return 0
    }
}


# ::etcd::XOpts -- Separate options and arguments
#
#       This utility procedure separates the options from the
#       arguments.  Options are dash-led (sometimes with a value)
#       while arguments will typically be blindly passed to the
#       server.  Whenever a -- (double dash) is present, it marks the
#       end of the options and the beginning of the arguments,
#       allowing arguments to contain dash and have the same value as
#       the options, if necessary.  At return time, the first variable
#       will contain the list of arguments, while the second will
#       contain the list of options.  This procedure supposes that the
#       next step is to consecutively run GetOpt on the second
#       variable.  When no -- is present, both variables will be made
#       aliases in the calling frame, so that modifying the list of
#       options also modifies the list of arguments.
#
# Arguments:
#	_argv	Pointer to list of incoming arguments
#	_opts	Pointer to list of options
#
# Results:
#       None.
#
# Side Effects:
#       None.
proc ::etcd::XOpts {_argv _opts} {
    upvar $_argv argv
    set i [lsearch -exact  $argv --]
    if { $i >= 0 } {
	upvar $_opts opts
	set opts [lrange $argv [expr {$i+1}] end]
	set argv [lrange $argv 0 [expr {$i-1}]]
    } else {
	uplevel upvar 0 $_argv $_opts
    }
}


# ::etcd::Identifier -- Create an identifier
#
#       Create a unique identifier within this namespace.
#
# Arguments:
#	pfx	String to prefix to the name of the identifier
#
# Results:
#       A unique identifier
#
# Side Effects:
#       None.
proc ::etcd::Identifier { {pfx "" } } {
    variable ETCD
    
    set unique [incr ETCD(idGene)]
    ::append unique [expr {[clock clicks -milliseconds] % $ETCD(idClamp)}]
    return [format "[namespace current]::${pfx}%.$ETCD(idFormat)d" $unique]
}


# ::etcd::WebOp -- ETCD compatible Web API call
#
#       This will call a running instance of the etcd daemon and
#       return the result of the operation.  If a timeout was
#       associated to the connection context, it will be used to
#       ensure that the remote call ends.  This procedure
#       automatically stores the successfull or erroneous results sent
#       back by the remote etcd to ease introspection and analysis
#       whenver necessary.
#
# Arguments:
#	cx	Connection context as return by ::new
#	op	HTTP method to call (GET, PUT, DELETE, etc.)
#	path	Path *after* keys namespace for call
#	args	List of key value pairs used to format the query
#
# Results:
#       Return an error on failure, or the data that was acquired from
#       the remote etcd server.
#
# Side Effects:
#       None.
proc ::etcd::WebOp { cx op path args } {
    variable ETCD
    upvar \#0 $cx C

    set op [string toupper $op]

    # Create the base URL using the protocol, host and port from the
    # context, but also the version prefix and the path passed as an
    # argument.
    set url "$C(-proto)://$C(-host):$C(-port)/[string trim $ETCD(version) /]/"
    append url [string trimleft $path "/"]
    
    # Construct the query using the remaining of the argumnets, if
    # any.
    set qry ""
    if { [llength $args] > 0 } {
	set qry [eval ::http::formatQuery $args]
    }

    # When we have a query and the operation is not PUT/POST append
    # the query to the URL.
    if { $qry ne "" && [lsearch [list PUT POST] $op] < 0 } {
	append url ?
	append url $qry
	set qry "";   # Mark that we've used it to ensure proper test later
    }

    Log 4 "Preparing to execute API call $url"
    
    # Start constructing a command that will get the URL, using the
    # timeout that is associated to the connection context.
    set cmd [list \
		 ::http::geturl $url \
		 -method $op]
    if { $C(-timeout) >= 0 } {
	lappend cmd -timeout $C(-timeout)
    }
    if { [string is true $C(-keepalive)] } {
	lappend cmd -keepalive 1
    } else {
	lappend cmd -keepalive 0
    }

    # Tell the command to perform a query if we still have a query,
    # i.e. if the operation was PUT or POST.
    if { $qry ne "" } {
	lappend cmd -query $qry
    }

    # Now execute the command and analyse result based on return
    # codes.
    if { [catch {eval $cmd} tok] == 0 } {
	set ncode [::http::ncode $tok]
	if { $ncode >= 200 && $ncode < 300 } {
	    # Anything that is 2XX is a success (201 is sometimes
	    # returned for example).
	    set C(lastData) [::http::data $tok]
	    ::http::cleanup $tok
	    Log 6 "Received $ncode response: $C(lastData)"
	    return $C(lastData)
	} else {
	    # Otherwise we have an error.
	    set err [::http::error $tok]
	    set C(lastData) [::http::data $tok]
	    Log 3 "Error; code: $ncode, error: $err, data: $C(lastData)"
	    ::http::cleanup $tok
	    set errMsg "Error when accessing $url: $err (code: $ncode)\
                        data: $C(lastData)"
	    # Better mediate error from etcd whenever possible.
	    if { [catch {::etcd::json::parse $C(lastData)} d] == 0 } {
		if { [dict exists $d errorCode] } {
		    set errMsg "etcd API error: [dict get $d message],\
                                code [dict get $d errorCode]"
		}
	    }
	    return -code error $errMsg
	}
    } else {
	return -code error "Could not contact etcd at $C(-host):$C(-port): $tok"
    }
    return ""
}



# ::etcd::read -- Get value of a key/dir
#
#       Return the current value of a key, if it exists.  Descriptive
#       errors will be thrown whenever relevant.  This procedure can
#       take a number of dashled options.  Once the options have been
#       parsed, the remaining arguments are passed to the API call to
#       form the query.  It is possible to force separation of the
#       options and arguments using a -- in case one of the arguments
#       or its value was similar to one of the options.  The known
#       options are:
#       -raw    Return raw JSON answer from etcd
#
# Arguments:
#	cx	Connection context as returned by new
#	key	Hierarchical path to key
#	args	Options to read and arguments to API call
#
# Results:
#       The raw JSON answer from etcd or the value of the key.  An
#       error is returned when the key was a directory and -raw wasn't
#       specified.
#
# Side Effects:
#       None.
proc ::etcd::read { cx key args } {
    # Separate options from arguments and capture -raw
    XOpts args opts
    set raw [GetOpt opts -raw]

    # Do API call
    set json [eval [linsert $args 0 \
			WebOp $cx GET keys/[string trimleft $key /]]]
    if { $raw } {
	return $json
    } else {
	# Parse JSON answer, detect directories and return the value
	# of proper keys.
	set d [::etcd::json::parse $json]
	if { [dict exists $d node] } {
	    set node [dict get $d node]
	    if { [dict exists $node dir] \
		     && [string is true [dict get $node dir]] } {
		return -code error "Key $key is a directory!"
	    }
	    return [dict get $node value]
	}
	return ""
    }
}


# ::etcd::write -- Set value to key/dir
#
#       Set the (new) value of a key, creating the key if it did not
#       exists.  Descriptive errors will be returned whenever
#       relevant.  This procedure can take a number of dashled
#       options.  Once the options have been parsed, the remaining
#       arguments are passed to the API call to form the query.  It is
#       possible to force separation of the options and arguments
#       using a -- in case one of the arguments or its value was
#       similar to one of the options.  The known options are:
#       -raw    Return raw JSON answer from etcd
#       -noval  Ignore value passed in val argument
#       -ignore Alias for -noval.
#
#       The additional arguments come in pairs (names and values) and
#       will be passed to the remote server.  Useful arguments are for
#       example: ttl to set the ttl of a key, or prevExist, prevIndex
#       or prevValue for atomic compare and swap.
#
# Arguments:
#	cx	Connection context as returned by new
#	key	Hierarchical path to key
#	val	New value for key (ignored when -noval specified)
#	args	Options to write and arguments to API call
#
# Results:
#       Return the raw JSON answer from etcd when -raw is specified,
#       or the previous value of the key at the daemon, if available.
#
# Side Effects:
#       None.
proc ::etcd::write { cx key val args } {
    XOpts args opts
    set noval [GetOpt opts -noval]
    if { !$noval} {
	set noval [GetOpt opts -ignore]
    }
    set raw [GetOpt opts -raw]

    if { $noval } {
	set json [eval [linsert $args 0 \
			    WebOp $cx PUT keys/[string trimleft $key /]]]
    } else {
	set json [eval [linsert $args 0 \
			    WebOp $cx PUT keys/[string trimleft $key /] \
			    value $val]]
    }

    if { $raw } {
	return $json
    } else {
	set d [::etcd::json::parse $json]
	if { [dict exists $d prevNode] } {
	    return [dict get [dict get $d prevNode] value]
	}
	return ""
    }
}


# ::etcd::delete -- Delete a key/dir
#
#       Delete a key or directory.  Descriptive errors will be thrown
#       whenever relevant.  This procedure can take a number of
#       dashled options.  Once the options have been parsed, the
#       remaining arguments are passed to the API call to form the
#       query.  It is possible to force separation of the options and
#       arguments using a -- in case one of the arguments or its value
#       was similar to one of the options.  The known options are:
#       -raw    Return raw JSON answer from etcd
#
#       The additional arguments come in pairs (names and values) and
#       will be passed to the remote server.  Useful arguments are for
#       example: recursive to delete recursively, or dir to specify
#       that the key is a directory (and not a regular key).
#
# Arguments:
#	cx	Connection context as returned by new
#	key	Hierarchical path to key/dir
#	args	Options to delete and arguments to API call
#
# Results:
#       Return the raw JSON answer from etcd when -raw is specified,
#       or the previous value of the key at the daemon, if available.
#
# Side Effects:
#       None.
proc ::etcd::delete { cx key args } {
    XOpts args opts
    set raw [GetOpt opts -raw]

    set json [eval [linsert $args 0 \
			WebOp $cx DELETE keys/[string trimleft $key /]]]
    if { $raw } {
	return $json
    } else {
	set d [::etcd::json::parse $json]
	if { [dict exists $d prevNode] } {
	    return [dict get [dict get $d prevNode] value]
	}
	return ""
    }
}


# ::etcd::machines -- List machines in cluster
#
#       List the URLs to the machines in the cluster.  Descriptive
#       errors will be thrown whenever relevant.
#
# Arguments:
#	cx	Connection context as returned by new
#
# Results:
#       List of machines
#
# Side Effects:
#       None.
proc ::etcd::machines { cx } {
    return [WebOp $cx GET machines]
}


# ::etcd::leader -- Leader of cluster
#
#       Return the URLs to the leader of the cluster.  Descriptive
#       errors will be thrown whenever relevant.
#
# Arguments:
#	cx	Connection context as returned by new
#
# Results:
#       Leader of cluster
#
# Side Effects:
#       None.
proc ::etcd::leader { cx } {
    return [WebOp $cx GET machines]
}

# ::etcd::mkdir -- Create a directory
#
#       Create a directory.  Descriptive errors will be thrown
#       whenever relevant.
#
# Arguments:
#	cx	Connection context as returned by new
#	dir	Hierarchical path to directory
#
# Results:
#       None.
#
# Side Effects:
#       None.
proc ::etcd::mkdir { cx dir } {
    # call write, making sure to ignore the value...
    return [write $cx $dir "" -ignore dir true]
}


# ::etcd::rmdir -- Remove directory
#
#       Remove directory.  Descriptive errors will be thrown
#       whenever relevant.
#
# Arguments:
#	cx	Connection context as returned by new
#	dir	Hierarchical path to directory
#	recur	Should deletion be recursive?
#
# Results:
#       None.
#
# Side Effects:
#       None.
proc ::etcd::rmdir { cx key {recur 0} } {
    if { $recur } {
	return [delete $cx $key -raw recursive true]
    } else {
	return [delete $cx $key -raw dir true]
    }
}


# ::etcd::Unwind -- Convert JSON data to descriptive triplets
#
#       Convert parts of the answer from recursive directory
#       traversals to the format that is output to callers,
#       i.e. triplets where the first item is the full path to the
#       directory or key, the second item a boolean telling if this is
#       a directory (1) or key (0), last the value of the key (if
#       relevant, otherwise an empty string).  Only directories and
#       keys which names match the pattern will be output
#
# Arguments:
#	d	Dictionary representing JSON content
#	ptn	Pattern to match against names
#
# Results:
#       A triplet as described above, or an empty list if name does
#       not match.
#
# Side Effects:
#       None.
proc ::etcd::Unwind { d ptn } {
    set n [dict get $d key]
    if { [string match $ptn [file tail $n]] } {
	set isdir 0
	if { [dict exists $d dir] && [dict get $d dir] } {
	    set isdir 1
	}
	set value ""
	if { [dict exists $d value] } {
	    set value [dict get $d value]
	}
	return [list $n $isdir $value]
    }
    return {}
}


# ::etcd::Recurse -- Recurse in directory traversals.
#
#       Recurse in directory traversals to return the list of keys and
#       directory names which name match the pattern passed as an
#       argument.
#
# Arguments:
#	d	Dictionary representing JSON traversal
#	ptn	Pattern to match against names
#
# Results:
#       A 3-ary list as where each triplet is as described in the
#       Unwind procedure.
#
# Side Effects:
#       None.
proc ::etcd::Recurse { d ptn } {
    if { [dict exists $d nodes] } {
	set subs [Unwind $d $ptn]
	foreach sd [dict get $d nodes] {
	    set subs [concat $subs [Recurse $sd $ptn]]
	}
	return $subs
    } else {
	return [Unwind $d $ptn]
    }
}


# ::etcd::glob -- List directory content (recursively)
#
#       (Recursively) traverse a directory for keys and directories
#       which names match the pattern passed as an argument.  This
#       procedure will return a 3-ary list where the triplets are
#       composed as follows: First item is the full path to the
#       directory or key; second item is a boolean telling if this is
#       a directory (1) or a regular key (0); last item is the value
#       of the key (if relevant, otherwise, this will be an empty
#       string).
#
# Arguments:
#	cx	Connection context as returned by new
#	dir	Hierarchical path to directory
#	recur	Should deletion be recursive?
#	ptn	Pattern to match against directory and key names
#
# Results:
#       Return a 3-ary list, as described above.
#
# Side Effects:
#       None.
proc ::etcd::glob { cx dir {recur 0} {ptn *} } {
    if { $recur } {
	set d [::etcd::json::parse [read $cx $dir -raw recursive true]]
    } else {
	set d [::etcd::json::parse [read $cx $dir -raw]]
    }
    return [Recurse [dict get $d node] $ptn]
}


# ::etcd::new -- Create new connection context
#
#       Create a new connection context to a remote etcd server.  At
#       present, there is no active attempt to connect to the server
#       to check for capabilities or similar.  This procedure can take
#       a number of dash-led options and their values as arguments.
#       These options are:
#       -host    The hostname of the remote server (default: localhost)
#       -port    The port number at the remote server (default: 4001)
#       -proto   http or https
#       -timeout Timeout when talking to server, in ms. Negative to turn off.
#
# Arguments:
#	args	List of dash-led options and their values, as described above.
#
# Results:
#       Return the identifier of the connection context to be used in
#       all further calls to this library.
#
# Side Effects:
#       None.
proc ::etcd::new { args } {
    variable ETCD

    set cx [Identifier etcd]
    upvar \#0 $cx C
    foreach k [array names ETCD -*] {
	GetOpt args $k C($k) $ETCD($k)
    }
    Log 5 "Created connection to etcd at $C(-host):$C(-port)"
    set C(lastData) ""

    return $cx
}


# ::etcd::find -- Find existing and matching contexts
#
#       Finds the list of existing context that match the arguments.
#       The arguments are in the form of dash-led options and their
#       values.  The options should be similar to the option used for
#       context creation, the values are glob-style patterns.
#
# Arguments:
#	args	See description above
#
# Results:
#       The list of matching contexts, empty if none.
#
# Side Effects:
#       None.
proc ::etcd::find { args } {
    variable ETCD

    set found [list]
    foreach cx [info vars [namespace current]::etcd*] {
	upvar \#0 $cx C
	set match 1
	foreach {k v} $args {
	    if { [info exist C($k)] && ![string match $v $C($k)] } {
		set match 0
	    }
	}
	if { $match } {
	    lappend found $cx
	}
    }
    return $found
}


# ::etcd::latest -- Return latest data from etcd
#
#       Return the lastest raw data returned by etcd in raw (JSON most
#       of the time) format.  This data is reset at each API call.
#
# Arguments:
#	cx	Connection context as returned by new
#
# Results:
#       Latest raw data from etcd server
#
# Side Effects:
#       None.
proc ::etcd::data { cx } {
    variable ETCD
    upvar \#0 $cx C
    return $C(lastData)
}


package provide etcd $::etcd::version
