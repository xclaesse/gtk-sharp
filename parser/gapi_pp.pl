#!/usr/bin/perl
#
# gapi_pp.pl : A source preprocessor for the extraction of API info from a
#	       C library source directory.
#
# Authors: Mike Kestner <mkestner@speakeasy.net>
# 	   Martin Willemoes Hansen <mwh@sysrq.dk>
#
# <c> 2001 Mike Kestner
# <c> 2003 Martin Willemoes Hansen
# <c> 2003 Novell, Inc.

$eatit_regex = "^#if.*(__cplusplus|DEBUG|DISABLE_(DEPRECATED|COMPAT)|ENABLE_BROKEN|COMPILATION)";
$ignoreit_regex = '^\s+\*|#ident|#\s*include|#\s*else|#\s*endif|#\s*undef|G_(BEGIN|END)_DECLS|extern|GDKVAR|GTKVAR|GTKMAIN_C_VAR|GTKTYPEUTILS_VAR|VARIABLE|GTKTYPEBUILTIN';

foreach $arg (@ARGV) {
	if (-d $arg && -e $arg) {
		@hdrs = (@hdrs, `ls $arg/*.h`);
		@srcs = (@srcs, `ls $arg/*.c`);
	} elsif (-f $arg && -e $arg) {
		@hdrs = (@hdrs, $arg) if ($arg =~ /\.h$/);
		@srcs = (@srcs, $arg) if ($arg =~ /\.c$/);
	} else {
		die "unable to process arg: $arg";
	}
}

foreach $fname (@hdrs) {

	if ($fname =~ /test|private|internals|gtktextlayout|gtkmarshalers/) {
		@privhdrs = (@privhdrs, $fname);
		next;
	}

	open(INFILE, $fname) || die "Could open $fname\n";

	$braces = 0;
	$prepend = "";
	while ($line = <INFILE>) {
		$braces++ if ($line =~ /{/ and $line !~ /}/);
		$braces-- if ($line =~ /}/ and $line !~ /{/);
		
		next if ($line =~ /$ignoreit_regex/);

		$line =~ s/\/\*.*?\*\///g;

		next if ($line !~ /\S/);

		$line = $prepend . $line;
		$prepend = "";

		if ($line =~ /#\s*define\s+\w+\s+\"/) {
			$def = $line;
			while ($def !~ /\".*\"/) {$def .= ($line = <INFILE>);}
			print $def;
		} elsif ($line =~ /#\s*define\s+\w+\s*\D+/) {
			$def = $line;
			while ($line =~ /\\\n/) {$def .= ($line = <INFILE>);}
			if ($def =~ /_CHECK_\w*CAST|INSTANCE_GET_INTERFACE/) {
				$def =~ s/\\\n//g;
				print $def;
			}
		} elsif ($line =~ /^\s*\/\*/) {
			while ($line !~ /\*\//) {$line = <INFILE>;}
		} elsif ($line =~ /^#ifndef\s+\w+_H_*\b/) {
			while ($line !~ /#define/) {$line = <INFILE>;}
		} elsif ($line =~ /$eatit_regex/) {
			$nested = 0;
			while ($line = <INFILE>) {
				last if (!$nested && ($line =~ /#else|#endif/));
				if ($line =~ /#if/) {
					$nested++;
				} elsif ($line =~ /#endif/) {
					$nested--
				}
			}
		} elsif ($line =~ /^#\s*ifn?\s*\!?def/) {
			#warn "Ignored #if:\n$line";
		} elsif ($line =~ /typedef struct\s*\{/) {
			my $first_line = $line;
			my @lines = ();
			$line = <INFILE>;
			while ($line !~ /^}\s*(\w+);/) {
				push @lines, $line;
				$line = <INFILE>;
			}
			$line =~ /^}\s*(\w+);/;
			my $name = $1;
			print "typedef struct _$name $name;\n";
			print "struct _$name {\n";
			foreach $line (@lines) {
				if ($line =~ /(\s*.+\;)/) {
					$field = $1;
					$field =~ s/(\w+) const/const $1/;
					print "$field\n";
				}
			}
			print "};\n";
		} elsif ($line =~ /^enum\s+\{/) {
			while ($line !~ /^};/) {$line = <INFILE>;}
		} elsif ($line =~ /(\s+)union\s*{/) {
			# this is a hack for now, but I need it for the fields to work
			$indent = $1;
			$do_print = 1;
			while ($line !~ /^$indent}\s*\w+;/) {
				$line = <INFILE>;
				next if ($line !~ /;/);
				print $line if $do_print;
				$do_print = 0;
			}
		} else {
			if ($braces or $line =~ /;/) {
				print $line;
			} else {
				$prepend = $line;
				$prepend =~ s/\n/ /g;
			}
		}
	}
}

foreach $fname (@srcs, @privhdrs) {

	open(INFILE, $fname) || die "Could open $fname\n";

	if ($fname =~ /builtins_ids/) {
		while ($line = <INFILE>) {
			next if ($line !~ /\{/);

			chomp($line);
			$builtin = "BUILTIN" . $line;
			$builtin .= <INFILE>;
			print $builtin;
		}
		next;
	}

	while ($line = <INFILE>) {
		#next if ($line !~ /^(struct|\w+_class_init)|g_boxed_type_register_static/);
		next if ($line !~ /^(struct|\w+_class_init|\w+_base_init|\w+_get_type)/);

		if ($line =~ /^struct/) {
			# need some of these to parse out parent types
			print "private";
		}

		$comment = 0;
		$begin = 0;
		$end = 0;
		do {
			# Following ifs strips out // and /* */ C comments
			if ($line =~ /\/\*/) {
				$comment = 1;
				$begin = 1;
			}

			if ($comment != 1) {
				$line =~ s/\/\/.*//;
				print $line;
			}

			if ($line =~ /\*\//) {
				$comment = 0;
				$end = 1;
			}

			if ($begin == 1 && $end == 1) {
				$line =~ s/\/\*.*\*\///;
				print $line;
			}

			$begin = 0;
			$end = 0;
		} until (($line = <INFILE>) =~ /^}/);
		print $line;
	}
}

