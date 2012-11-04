use strict;
use warnings;
use Path::Class;
use lib file(__FILE__)->dir->parent->subdir('t_deps', 'modules', 'test-x1', 'lib')->stringify;
use Test::X1;
use Test::More;
use Time::HiRes qw(time);
use AnyEvent::Timer::Retry;

test {
  my $c = shift;

  my $result = [];
  my $invoked = sub {
    #note $_[0];
    push @$result, $_[0];
  };

  my $start_time = time;
  my $i = 0;
  my $timer; $timer = AnyEvent::Timer::Retry->new
      (on_retry => sub {
         my $done = shift;
         test {
           $invoked->($timer->retry_count);
           is $timer->retry_count, $i++;
           $done->($timer->retry_count == 10, "abc");
         } $c;
       },
       on_end => sub {
         my ($r, $value) = @_;
         test {
           is !!$r, $i == 11;
           is $value, "abc";
           is_deeply $result, [0..10];
           my $elapsed = time - $start_time;
           ok $elapsed < 0.1 * 10 + 2;
           ok $elapsed > 0.1 * 10 - 2;
           undef $timer;
           done $c;
           undef $c;
         } $c;
       },
       interval => 0.1);
} n => 11 + 5, name => 'basic';

test {
  my $c = shift;
  my $start_time = time;
  my $timer; $timer = AnyEvent::Timer::Retry->new
      (on_retry => sub {
         #
       },
       on_end => sub {
         test {
           my $elapsed = time - $start_time;
           ok $elapsed < 2 + 1;
           ok $elapsed > 2 - 1;
           done $c;
           undef $c;
           undef $timer;
         } $c;
       },
       timeout => 2);
} n => 2, name => 'global timeout';

test {
  my $c = shift;
  my $start_time = time;
  my $cv = AE::cv;
  $cv->begin;
  $cv->begin;
  $cv->begin;
  my $i = 0;
  my $timer; $timer = AnyEvent::Timer::Retry->new
      (on_retry => sub {
         my $done = $_[0];
         my $w; $w = AE::timer 3, 0, sub {
           $done->(1);
           undef $w;
           $i++;
           $cv->end;
         };
       },
       on_end => sub {
         my $ok = $_[0];
         test {
           ok !$ok;
           $cv->end;
           undef $timer;
         } $c;
       },
       interval => 0.1,
       timeout => 1);
  $cv->end;
  $cv->cb(sub {
    test {
      is $i, 1;
      done $c;
      undef $c;
    } $c;
  });
} n => 2, name => 'ok after global timeout';

test {
  my $c = shift;
  my $cv = AE::cv;
  my $i = 0;
  $cv->begin;
  $cv->begin;
  my $timer; $timer = AnyEvent::Timer::Retry->new
      (on_retry => sub { },
       on_end => sub {
         test {
           is $i++, 0;
           undef $timer;
           $cv->end;
         } $c;
       },
       timeout => 0);
  $cv->begin;
  my $w; $w = AE::timer 100, 0, sub {
    test {
      is $i++, 1;
      $cv->end;
      undef $w;
    } $c;
  };
  $cv->end;
  $cv->cb(sub {
    test {
      done $c;
      undef $c;
    } $c;
  });
} n => 2, name => 'no global timeout';

test {
  my $c = shift;
  
  my $start_time = time;
  my $timer; $timer = AnyEvent::Timer::Retry->new
      (on_retry => sub {
         $_[0]->($timer->retry_count == 1);
       },
       on_end => sub {
         test {
           my $elapsed = time - $start_time;
           #note $elapsed;
           ok $elapsed < 1 + 2;
           ok $elapsed > 0.5;
           undef $timer;
           done $c;
           undef $c;
         } $c;
       });
} n => 2, name => 'start_interval default';

test {
  my $c = shift;
  my $cv = AE::cv;
  $cv->begin;
  $cv->begin;
  $cv->begin;
  my $retry_invoked = 0;
  my $done_invoked = 0;
  my $timer; $timer = AnyEvent::Timer::Retry->new
      (on_retry => sub {
         my $done = $_[0];
         test {
           $retry_invoked++;
           $done->(1);
           $done->(0);
           $cv->end;
         } $c;
       },
       on_end => sub {
         test {
           $done_invoked++;
           is $timer->retry_count, 0;
           undef $timer;
           $cv->end;
         } $c;
       });
  $cv->end;
  $cv->cb(sub {
    test {
      is $retry_invoked, 1;
      is $done_invoked, 1;
      done $c;
      undef $c;
    } $c;
  });
} n => 3, name => 'set_result multiple invocations';

test {
  my $c = shift;
  my $retry_invoked = 0;
  my $done_invoked = 0;
  my $code;
  my $timer; $timer = AnyEvent::Timer::Retry->new
      (on_retry => sub {
         $retry_invoked++;
         $code = $_[0];
         $_[0]->(1);
       },
       on_end => sub {
         $done_invoked++;
         $code->(0);
         test {
           is $retry_invoked, 1;
           is $done_invoked, 1;
           done $c;
           undef $c;
           undef $timer;
         } $c;
       });
} n => 2, name => 'set_result after retry';

test {
  my $c = shift;
  my $i = 0;
  my $timer; $timer = AnyEvent::Timer::Retry->new
      (on_retry => sub {
         $i++;
         if ($timer->retry_count == 1) {
           undef $timer;
         } else {
           $_[0]->(0);
         }
       },
       on_end => sub {
         test {
           is $timer, undef;
           is $i, 2;
           done $c;
           undef $c;
         } $c;
       },
       interval => 0.1);
} n => 2, name => 'cancelled by undef $timer';

test {
  my $c = shift;
  my $i = 0;
  my $timer; $timer = AnyEvent::Timer::Retry->new
      (on_retry => sub {
         $i++;
         if ($timer->retry_count == 1) {
           $timer->cancel;
           $timer->cancel;
         } else {
           $_[0]->(0);
         }
       },
       on_end => sub {
         test {
           is $timer->retry_count, 1;
           is $i, 2;
           done $c;
           undef $c;
           undef $timer;
         } $c;
       },
       interval => 0.1);
} n => 2, name => 'cancelled by $timer->cancel';

test {
  my $c = shift;
  my $cv = AE::cv;
  $cv->begin;
  $cv->begin; # on_retry
  $cv->begin; # on_end
  my $i = 0;
  my $j = 0;
  my $timer; $timer = AnyEvent::Timer::Retry->new
      (on_retry => sub {
         my $done = shift;
         test {
           if ($timer->retry_count > 2) {
             $done->(1, 3);
             $cv->end; # on_retry
           } else {
             $i++;
             $cv->begin;
             my $w; $w = AE::timer 0.8, 0, sub {
               test {
                 $j++;
                 $done->(1, 2);
                 undef $w;
                 $cv->end;
               } $c;
             };
           }
         } $c;
       },
       on_end => sub {
         my ($result, $data) = @_;
         test {
           ok $result;
           is $data, 3;
           $cv->end;
           undef $timer;
         } $c;
       },
       interval => 0.1,
       retry_timeout => 0.4);
  $cv->end;
  $cv->cb(sub {
    test {
      is $j, $i;
      done $c;
      undef $c;
    } $c;
  });
} n => 3, name => 'local timeout';

test {
  my $c = shift;
  my $start_time = time;
  my $timer; $timer = AnyEvent::Timer::Retry->new
      (on_retry => sub {
         #
       },
       on_end => sub {
         my $result = shift;
         test {
           ok !$result;
           my $elapsed = time - $start_time;
           ok $elapsed < 2 + 1;
           ok $elapsed > 2 - 1;
           done $c;
           undef $c;
           undef $timer;
         } $c;
       },
       retry_timeout => undef,
       timeout => 2);
} n => 3, name => 'no local timeout';

test {
  my $c = shift;
  my $invoked;
  eval {
    my $timer; $timer = AnyEvent::Timer::Retry->new
        (on_end => sub { $invoked = 1; undef $timer });
    ok !1;
    1;
  } or do {
    ok $@ =~ /on_retry/;
  };
  ok !$invoked;
  done $c;
  undef $c;
} n => 2, name => 'no on_retry';

test {
  my $c = shift;
  my $invoked;
  eval {
    my $timer; $timer = AnyEvent::Timer::Retry->new
        (on_retry => sub { $invoked = 1; undef $timer });
    ok !1;
    1;
  } or do {
    ok $@ =~ /on_end/;
  };
  ok !$invoked;
  done $c;
  undef $c;
} n => 2, name => 'no on_end';

run_tests;

=head1 LICENSE

Copyright 2012 Wakaba <wakaba@suikawiki.org>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
