package AnyEvent::Timer::Retry;
use strict;
use warnings;
use AnyEvent;
use Scalar::Util qw(weaken);

sub new ($%) {
  my $class = shift;
  my $self = bless {@_, retry_count => 0}, $class;
  if (my $timeout = $self->timeout) {
    weaken (my $self = $self);
    $self->{timer}->{global} = AE::timer $timeout, 0, sub {
      $self->cancel if $self;
    };
  }
  $self->_try (0);
  return $self;
} # new

sub _try ($$) {
  weaken (my $self = shift);
  my $interval = shift;
  my $n = $self->{retry_count};
  $self->{timer}->{$n} = AE::timer $interval, 0, sub {
    return unless $self;
    $self->{on_retry}->($self);
    undef $self->{timer}->{$n};
  };
} # _try

sub set_result ($$) {
  my ($self, $result, $value) = @_;
  if ($self->{result_set}->{$self->{retry_count}}++) {
    return;
  }
  if ($result = !!$result or $self->{done}) {
    my $timer; $timer = AE::timer 0, 0, sub {
      $self->{on_done}->($self, $result, $value);
      undef $timer;
    };
    delete $_[0]->{timer};
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

sub timeout ($) {
  return $_[0]->{timeout} || 60;
} # timeout

sub cancel ($) {
  $_[0]->{done} = 1;
  $_[0]->set_result (0);
} # cancel

sub DESTROY {
  $_[0]->cancel;
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
