#!/usr/bin/perl -w
#
# This script parses remote_protocol.x and produces lots of boilerplate
# code for both ends of the remote connection.
#
# By Richard Jones <rjones@redhat.com>

use strict;

use Getopt::Std;

# Command line options.
our ($opt_p, $opt_t, $opt_a, $opt_r, $opt_d);
getopts ('ptard');

# Convert name_of_call to NameOfCall.
sub name_to_ProcName {
    my $name = shift;
    my @elems = split /_/, $name;
    @elems = map ucfirst, @elems;
    join "", @elems
}

# Read the input file (usually remote_protocol.x) and form an
# opinion about the name, args and return type of each RPC.
my ($name, $ProcName, $id, %calls, @calls);

# REMOTE_PROC_CLOSE has no args or ret.
$calls{close} = {
    name => "close",
    ProcName => "Close",
    UC_NAME => "CLOSE",
    args => "void",
    ret => "void",
};

while (<>) {
    if (/^struct remote_(.*)_args/) {
	$name = $1;
	$ProcName = name_to_ProcName ($name);

	die "duplicate definition of remote_${name}_args"
	    if exists $calls{$name};

	$calls{$name} = {
	    name => $name,
	    ProcName => $ProcName,
	    UC_NAME => uc $name,
	    args => "remote_${name}_args",
	    ret => "void",
	};

    } elsif (/^struct remote_(.*)_ret/) {
	$name = $1;
	$ProcName = name_to_ProcName ($name);

	if (exists $calls{$name}) {
	    $calls{$name}->{ret} = "remote_${name}_ret";
	} else {
	    $calls{$name} = {
		name => $name,
		ProcName => $ProcName,
		UC_NAME => uc $name,
		args => "void",
		ret => "remote_${name}_ret"
	    }
	}
    } elsif (/^struct remote_(.*)_msg/) {
	$name = $1;
	$ProcName = name_to_ProcName ($name);

	$calls{$name} = {
	    name => $name,
	    ProcName => $ProcName,
	    UC_NAME => uc $name,
	    msg => "remote_${name}_msg"
	}
    } elsif (/^\s*REMOTE_PROC_(.*?)\s+=\s+(\d+),?$/) {
	$name = lc $1;
	$id = $2;
	$ProcName = name_to_ProcName ($name);

	$calls[$id] = $calls{$name};
    }
}

#----------------------------------------------------------------------
# Output

print <<__EOF__;
/* Automatically generated by remote_generate_stubs.pl.
 * Do not edit this file.  Any changes you make will be lost.
 */

__EOF__

# Debugging.
if ($opt_d) {
    my @keys = sort (keys %calls);
    foreach (@keys) {
	print "$_:\n";
	print "        name $calls{$_}->{name} ($calls{$_}->{ProcName})\n";
	print "        $calls{$_}->{args} -> $calls{$_}->{ret}\n";
    }
}

# Prototypes for dispatch functions ("remote_dispatch_prototypes.h").
elsif ($opt_p) {
    my @keys = sort (keys %calls);
    foreach (@keys) {
	# Skip things which are REMOTE_MESSAGE
	next if $calls{$_}->{msg};

	print "static int remoteDispatch$calls{$_}->{ProcName}(\n";
	print "    struct qemud_server *server,\n";
	print "    struct qemud_client *client,\n";
	print "    virConnectPtr conn,\n";
	print "    remote_message_header *hdr,\n";
	print "    remote_error *err,\n";
	print "    $calls{$_}->{args} *args,\n";
	print "    $calls{$_}->{ret} *ret);\n";
    }
}

# Union of all arg types
# ("remote_dispatch_args.h").
elsif ($opt_a) {
    for ($id = 0 ; $id <= $#calls ; $id++) {
	if (defined $calls[$id] &&
	    !$calls[$id]->{msg} &&
	    $calls[$id]->{args} ne "void") {
	    print "    $calls[$id]->{args} val_$calls[$id]->{args};\n";
	}
    }
}

# Union of all arg types
# ("remote_dispatch_ret.h").
elsif ($opt_r) {
    for ($id = 0 ; $id <= $#calls ; $id++) {
	if (defined $calls[$id] &&
	    !$calls[$id]->{msg} &&
	    $calls[$id]->{ret} ne "void") {
	    print "    $calls[$id]->{ret} val_$calls[$id]->{ret};\n";
	}
    }
}

# Inside the switch statement, prepare the 'fn', 'args_filter', etc
# ("remote_dispatch_table.h").
elsif ($opt_t) {
    for ($id = 0 ; $id <= $#calls ; $id++) {
	if (defined $calls[$id] && !$calls[$id]->{msg}) {
	    print "{   /* $calls[$id]->{ProcName} => $id */\n";
	    print "    .fn = (dispatch_fn) remoteDispatch$calls[$id]->{ProcName},\n";
	    if ($calls[$id]->{args} ne "void") {
		print "    .args_filter = (xdrproc_t) xdr_$calls[$id]->{args},\n";
	    } else {
		print "    .args_filter = (xdrproc_t) xdr_void,\n";
	    }
	    if ($calls[$id]->{ret} ne "void") {
		print "    .ret_filter = (xdrproc_t) xdr_$calls[$id]->{ret},\n";
	    } else {
		print "    .ret_filter = (xdrproc_t) xdr_void,\n";
	    }
	    print "},\n";
	} else {
	    if ($calls[$id]->{msg}) {
		print "{   /* Async event $calls[$id]->{ProcName} => $id */\n";
	    } else {
		print "{   /* (unused) => $id */\n";
	    }
	    print "    .fn = NULL,\n";
	    print "    .args_filter = (xdrproc_t) xdr_void,\n";
	    print "    .ret_filter = (xdrproc_t) xdr_void,\n";
	    print "},\n";
	}
    }
}
