package Devel::SmallProf; # To help the CPAN indexer to identify us

$Devel::SmallProf::VERSION = '0.5';

package DB;

require 5.000;

use Time::HiRes 'time';

use strict;

BEGIN {
  $DB::drop_zeros = 0;
  $DB::profile = 1;
  if (-e '.smallprof') {
    do '.smallprof';
  }
  $DB::prevf = '';
  $DB::prevl = 0;
  my($diff);

  my($testDB) = sub {
    my($pkg,$filename,$line) = caller;
    $DB::profile || return;
    %DB::packages && !$DB::packages{$pkg} && return;
  };

  # "Null time" compensation code
  $DB::nulltime = 0;
  for (1..100) {
    $DB::start = time;
    &$testDB;
    $DB::done = time;
    $diff = $DB::done - $DB::start;
    $DB::nulltime += $diff;
  }
  $DB::nulltime /= 100;

  $DB::start = time;
}

sub DB {
  my($pkg,$filename,$line) = caller;
  $DB::profile || return;
  %DB::packages && !$DB::packages{$pkg} && return;
  $DB::done = time;

  # Now save the _< array for later reference.  If we don't do this here, 
  # evals which do not define subroutines will disappear.
  no strict 'refs';
  $DB::listings{$filename} = \@{"main::_<$filename"} if 
    defined(@{"main::_<$filename"});
  use strict 'refs';

  my($delta);
  $delta = $DB::done - $DB::start;
  $delta = ($delta > $DB::nulltime) ? $delta - $DB::nulltime : 0;
  $DB::profiles{$filename}->[$line]++;
  $DB::times{$DB::prevf}->[$DB::prevl] += $delta;
  ($DB::prevf, $DB::prevl) = ($filename, $line);

  $DB::start = time;
}

END {
  # Get time on last line executed.
  $DB::done = time;
  my($delta);
  $delta = $DB::done - $DB::start;
  $delta = ($delta > $DB::nulltime) ? $delta - $DB::nulltime : 0;
  $DB::times{$DB::prevf}->[$DB::prevl] += $delta;

  # Now write out the results.
  open(OUT,">smallprof.out");
  select OUT;
  my($i,$stat,$time,$line,$file,$page);
  $page = 1;

format OUT_TOP=
===============================================================================
         @|||||||||||||||||||||||||||||||||||||||||||||||||||||||||||| Page @<<
"Profile of $file",$page++
===============================================================================
.
format OUT= 
@##### @.###### @####:^<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
$stat,$time,$i,$line
.
format OUT2= 
@##### @.###### @####:^<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
$stat,$time,$i,$line
~~                    ^<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
$line
.

  foreach $file (sort keys %DB::profiles) {
    $- = 0;
    if (defined($DB::listings{$file})) {
      $i = -1;
      foreach $line (@{$DB::listings{$file}}) {
        ++$i or next;
        chomp($line);
        $stat = $DB::profiles{$file}->[$i] || 0 or !$DB::drop_zeros or next;
        $time = defined($DB::times{$file}->[$i]) ?
                        $DB::times{$file}->[$i] : 0;
        write OUT;
      }
    } else {
      $line = "The code for $file is not in the symbol table.";
      for ($i=1; $i <= $#{$DB::profiles{$file}}; $i++) {
        next unless 
          ($stat = $DB::profiles{$file}->[$i] || 0 or !$DB::drop_zeros);
        $time = defined($DB::times{$file}->[$i]) ?
                        $DB::times{$file}->[$i] : 0;
        write OUT;
      } 
    }
  }
  close OUT;
}

sub sub {
  no strict 'refs';
  goto &$DB::sub unless $DB::profile;
  $DB::sub{$DB::sub} =~ /(.*):(\d+)-/;
  $DB::profiles{$1}->[$2]++ if defined $2;
  $DB::listings{$1} = \@{"main::_<$1"} if defined(@{"main::_<$1"});
  &$DB::sub;
  use strict 'refs';
}

1;

__END__

=head1 NAME

Devel::SmallProf - per-line Perl profiler

=head1 SYNOPSIS

	perl5 -d:SmallProf test.pl

=head1 DESCRIPTION

The Devel::SmallProf profiler is focused on the time taken for a program run on
a line-by-line basis.  It is intended to be as "small" in terms of impact on
the speed and memory usage of the profiled program as possible and also in
terms of being simple to use.  Those statistics are placed in the file
F<smallprof.out> in the following format:

        <num> <time> <file>:<line>:<text>

where <num> is the number of times that the line was executed, <time> is the
amount of time spent executing it and <file>, <line> and <text> are the 
filename, the line number and the actual text of the executed line (read from
the file).

The package uses the debugging hooks in Perl and thus needs the B<-d> switch,
so to profile F<test.pl>, use the command:

	perl5 -d:SmallProf test.pl

Once the script is done, the statistics in F<smallprof.out> can be sorted to 
show which lines took the most time.  The output can be sorted to find which
lines take the longest, either with the sort command:

	sort -nrk 2 smallprof.out | less

or a perl script:

	open(PROF,"smallprof.out");
	@sorted = sort {(split(/\s+/,$b))[2] <=> 
                        (split(/\s+/,$a))[2]} <PROF>;
        close PROF;
	print join('',@sorted);

=head1 NOTES

=over 4

=item * 

The timings are made with "wall time" (time in real life vs. cpu usage).  I'd
like eventually to report cpu time, but that isn't terribly easy to get 
across platforms.

=item *

SmallProf does attempt to make up for its shortcomings by subtracting a small
amount from each timing (null time compensation).  This should help somewhat
with the accuracy.

=item * 

SmallProf depends on the Time::HiRes package to do its timings except for the
Win32 version which depends on Win32::API.

=back

=head1 OPTIONS

SmallProf has 3 variables which can be used during your script to affect what
gets profiled.

=over 4

=item *

If you do not wish to see lines which were never called, set the variable
C<$DB::drop_zeros = 1>.  With C<drop_zeros> set, SmallProf can be used for 
basic coverage analysis.

=item *

To turn off profiling for a time, insert a C<$DB::profile = 0> into your code
(profiling may be turned back on with C<$DB::profile = 1>).  All of the time
between profiling being turned off and back on again will be lumped together 
and reported on the C<$DB::profile = 0> line.  This can be used to summarize a
subroutine call or a chunk of code.

=item *

To only profile code in a certain package, set the C<%DB::packages> array.  For
example, to see only the code in packages C<main> and C<Test1>, do this:

	%DB::packages = ( 'main' => 1, 'Test1' => 1 );

=item *

These variables can be put in a file called F<.smallprof> in the current 
directory.  For example, a F<.smallprof> containing

	$DB::drop_zeros = 1;
	$DB::profile = 0;

will set SmallProf to not report lines which are never touched for any file
profiled in that directory and will set profiling off initially (presumably to
be turned on only for a small portion of code).

=back

=head1 INSTALLATION

Just the usual

	perl Makefile.PL
	make
	make test
	make install

and should install fine via the CPAN module.  Makefile.PL checks to see if this
is a Win32 platform and runs a conversion subroutine on SmallProf prior to
installation.

=head1 BUGS

Subroutine calls are currently not under the control of %DB::packages.  This
should not be a great inconvenience in general.  

The handling of evals is bad news.  This is due to Perl's handling of evals 
under the B<-d> flag.  For certain evals, caller() returns '(eval n)' for the 
filename and for others it doesn't.  For some of those which it does, the array
C<@{'_E<lt>filename'}> contains the code of the eval.  For others it doesn't.
Sometime, when I've an extra tuit or two, I'll figure out why and how I can 
compensate for this.

Comments, advice and questions are welcome.  If you see
inefficent stuff in this module and have a better way, please let me know.

=head1 AUTHOR
 
Ted Ashton E<lt>ashted@southern.eduE<gt>
 
SmallProf was developed from code originally posted to usenet by Philippe
Verdret E<lt>philippe.verdret@sonovision-itep.frE<gt>.  Special thanks to
Geoffrey Broadwell E<lt>habusan2@sprynet.comE<gt> for the Win32 code.
 
Copyright (c) 1997 Ted Ashton
 
This module is free software and can be redistributed and/or modified under the
same terms as Perl itself.

=head1 SEE ALSO

L<Devel::DProf>, L<Time::HiRes>, L<Win32::API>

=cut
