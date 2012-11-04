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
         my $timer = shift;
         test {
           $invoked->($timer->retry_count);
           is $timer->retry_count, $i++;
           $timer->set_result($timer->retry_count == 10, "abc");
         } $c;
       },
       on_done => sub {
         my (undef, $r, $value) = @_;
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
       initial_interval => 0.1);
} n => 11 + 5, name => 'basic';

test {
  my $c = shift;
  
  my $start_time = time;
  my $timer; $timer = AnyEvent::Timer::Retry->new
      (on_retry => sub {
         $_[0]->set_result($_[0]->retry_count == 1);
       },
       on_done => sub {
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
         test {
           $retry_invoked++;
           $timer->set_result (1);
           $timer->set_result (0);
           $cv->end;
         } $c;
       },
       on_done => sub {
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
  my $timer; $timer = AnyEvent::Timer::Retry->new
      (on_retry => sub {
         $retry_invoked++;
         $_[0]->set_result (1);
       },
       on_done => sub {
         $done_invoked++;
         $_[0]->set_result (0);
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
           $timer->set_result (0);
         }
       },
       on_done => sub {
         my $t = shift;
         test {
           is $timer, undef;
           is $t->retry_count, 1;
           is $i, 2;
           done $c;
           undef $c;
         } $c;
       },
       initial_interval => 0.1);
} n => 3, name => 'cancelled by undef $timer';

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
           $timer->set_result (0);
         }
       },
       on_done => sub {
         test {
           is $timer->retry_count, 1;
           is $i, 2;
           done $c;
           undef $c;
           undef $timer;
         } $c;
       },
       initial_interval => 0.1);
} n => 2, name => 'cancelled by $timer->cancel';

run_tests;

=head1 LICENSE

Copyright 2012 Wakaba <wakaba@suikawiki.org>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
