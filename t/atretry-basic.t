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
  AnyEvent::Timer::Retry->new
      (on_retry => sub {
         my $timer = shift;
         test {
           $invoked->($timer->retry_count);
           is $timer->retry_count, $i++;
           $timer->set_result($timer->retry_count == 10, "abc");
         } $c;
       },
       on_done => sub {
         my ($timer, $r, $value) = @_;
         test {
           is !!$r, $i == 11;
           is $value, "abc";
           is_deeply $result, [0..10];
           my $elapsed = time - $start_time;
           ok $elapsed < 0.1 * 10 + 2;
           ok $elapsed > 0.1 * 10 - 2;
           done $c;
           undef $c;
         } $c;
       },
       initial_interval => 0.1);
} n => 11 + 5, name => 'basic';

test {
  my $c = shift;
  
  my $start_time = time;
  AnyEvent::Timer::Retry->new
      (on_retry => sub {
         $_[0]->set_result($_[0]->retry_count == 1);
       },
       on_done => sub {
         test {
           my $elapsed = time - $start_time;
           #note $elapsed;
           ok $elapsed < 1 + 2;
           ok $elapsed > 0.5;
           done $c;
           undef $c;
         } $c;
       });
} n => 2, name => 'start_interval default';

run_tests;

=head1 LICENSE

Copyright 2012 Wakaba <wakaba@suikawiki.org>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
