package AnyEvent::Timer::Retry;
use strict;
use warnings;
use Carp qw(croak);
use AnyEvent;
use Scalar::Util qw(weaken);

sub new ($%) {
  my $class = shift;
  my $values = {@_, retry_count => 0};
  croak "No |on_retry|" unless $values->{on_retry};
  croak "No |on_end|" unless $values->{on_end};
  my $self = bless $values, $class;
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
  $self->{timer}->{try}->{$n} = AE::timer $interval, 0, sub {
    return unless $self;
    my $retry_timeout = $self->_get_next_retry_timeout;
    $self->{timer}->{timeout}->{$n} = AE::timer $retry_timeout, 0, sub {
      return unless $self;
      $self->_set_result ($n, 0);
      delete $self->{timer}->{timeout}->{$n};
    } if $retry_timeout;
    $self->{on_retry}->(sub {
      $self->_set_result ($n, @_) if $self;
    });
    undef $self->{timer}->{try}->{$n};
  };
} # _try

sub _set_result ($$$$) {
  my ($self, $n, $result, $value) = @_;
  return if $self->{result_set}->{$n}++;
  if ($result = !!$result or $self->{done}) {
    my $timer; $timer = AE::timer 0, 0, sub {
      $self->{on_end}->($result, $value);
      undef $timer;
    };
    delete $_[0]->{timer};
  } else {
    delete $_[0]->{timer}->{timeout}->{$n};
    $self->{retry_count}++;
    $self->_try ($self->_get_next_interval);
  }
} # _set_result

sub retry_count ($) {
  return $_[0]->{retry_count};
} # retry_count

sub interval ($) {
  return $_[0]->{interval} || 1;
} # initial_interval

sub _get_next_interval ($) {
  my $self = shift;
  return $self->interval;
} # get_next_interval

sub timeout ($) {
  return $_[0]->{timeout} || 60;
} # timeout

sub retry_timeout ($) {
  return $_[0]->{retry_timeout} || 60;
} # retry_timeout

sub _get_next_retry_timeout ($) {
  return $_[0]->retry_timeout;
} # _get_next_retry_timeout

sub cancel ($) {
  $_[0]->{done} = 1;
  $_[0]->_set_result ($_[0]->{retry_count}, 0);
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
