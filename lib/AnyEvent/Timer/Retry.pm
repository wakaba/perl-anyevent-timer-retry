package AnyEvent::Timer::Retry;
use strict;
use warnings;
use AnyEvent;

sub new ($%) {
  my $class = shift;
  my $self = bless {@_, retry_count => 0}, $class;
  $self->_try (0);
  return $self;
} # new

sub _try ($$) {
  my ($self, $interval) = @_;
  my $timer; $timer = AE::timer $interval, 0, sub {
    $self->{on_retry}->($self);
    undef $timer;
  };
} # _try

sub set_result ($$) {
  my ($self, $result, $value) = @_;
  if ($self->{result} = !!$result) {
    $self->{on_done}->($self, $self->{result}, $value);
  } else {
    $self->{retry_count}++;
    $self->_try ($self->get_next_interval);
  }
} # set_result

sub retry_count ($) {
  return $_[0]->{retry_count};
} # retry_count

sub initial_interval ($) {
  return $_[0]->{initial_interval} || 1;
} # initial_interval

sub get_next_interval ($) {
  my $self = shift;
  return $self->initial_interval;
} # get_next_interval

sub DESTROY {
  {
    local $@;
    eval { die };
    if ($@ =~ /during global destruction/) {
      warn "Possible memory leak detected";
    }
  }
} # DESTROY

1;

=head1 LICENSE

Copyright 2012 Wakaba <wakaba@suikawiki.org>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
