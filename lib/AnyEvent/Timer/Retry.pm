package AnyEvent::Timer::Retry;
use strict;
use warnings;
use Carp qw(croak);
use AnyEvent;
use Scalar::Util qw(weaken);
use Time::HiRes qw(time);

our $BackoffAlgorithms;

sub new ($%) {
  my $class = shift;
  my $values = {@_, retry_count => 0};
  croak "No |on_retry|" unless $values->{on_retry};
  croak "No |on_end|" unless $values->{on_end};
  croak "Unknown backoff method |$values->{interval_backoff}| is specified to |interval_backoff|"
      if $values->{interval_backoff} and
         not $BackoffAlgorithms->{$values->{interval_backoff}};
  croak "Unknown backoff method |$values->{retry_timeout_backoff}| is specified to |retry_timeout_backoff|"
      if $values->{retry_timeout_backoff} and
         not $BackoffAlgorithms->{$values->{retry_timeout_backoff}};
  my $self = bless $values, $class;
  $self->{start_time} = time;
  my $timeout = $self->timeout;
  if (defined $timeout and $timeout >= 0) {
    weaken (my $self = $self);
    $self->{timer}->{global} = AE::timer $timeout, 0, sub {
      $self->cancel if $self;
    };
    $self->on_info(message => "Timeout ($timeout s)");
  }
  $self->_try (0);
  return $self;
} # new

sub on_info ($) {
  return $_[0]->{on_info} ||= sub {
    my %args = @_;
    warn $args{message}, "\n";
  };
} # on_info

sub _try ($$) {
  weaken (my $self = shift);
  my $interval = shift;
  my $n = $self->{retry_count};
  $self->{timer}->{try}->{$n} = AE::timer $interval, 0, sub {
    return unless $self;
    my $retry_timeout = $self->{current_retry_timeout}
        = $self->_get_next_retry_timeout;
    if (defined $retry_timeout and $retry_timeout >= 0) {
      $self->{timer}->{timeout}->{$n} = AE::timer $retry_timeout, 0, sub {
        return unless $self;
        $self->on_info->(message => "Timeout (n = $n, $retry_timeout s)");
        $self->_set_result ($n, 0);
        delete $self->{timer}->{timeout}->{$n};
      };
    }
    $self->{on_retry}->(sub {
      $self->_set_result ($n, @_) if $self;
    });
    undef $self->{timer}->{try}->{$n};
  };
  $self->on_info->(message => "Retry after $interval s (n = $n)") if $n;
} # _try

sub _set_result ($$$$) {
  my ($self, $n, $result, $value) = @_;
  return if $self->{result_set}->{$n}++;
  if ($result = !!$result or $self->{done} or
      (defined $self->{max_retry_count} and $self->{max_retry_count} <= $n)) {
    my $timer; $timer = AE::timer 0, 0, sub {
      $self->{on_end}->($result, $value);
      undef $timer;
    };
    delete $_[0]->{timer};
  } else {
    delete $_[0]->{timer}->{timeout}->{$n};
    $self->{retry_count}++;
    $self->_try ($self->{current_interval} = $self->_get_next_interval);
  }
} # _set_result

sub retry_count ($) {
  return $_[0]->{retry_count};
} # retry_count

sub interval ($) {
  return $_[0]->{interval} || 1;
} # interval

sub current_interval ($) {
  return $_[0]->{current_interval} || 0;
} # current_interval

sub interval_backoff ($) {
  return $_[0]->{interval_backoff} || 'exponential';
} # interval_backoff

sub _get_next_interval ($) {
  my $self = shift;
  my $method = $self->interval_backoff;
  return $BackoffAlgorithms->{$method}->('interval', $self);
} # get_next_interval

sub timeout ($) {
  return defined $_[0]->{timeout} ? $_[0]->{timeout} : 60;
} # timeout

sub retry_timeout ($) {
  return defined $_[0]->{retry_timeout} ? $_[0]->{retry_timeout} : 60;
} # retry_timeout

sub current_retry_timeout ($) {
  return $_[0]->{current_retry_timeout};
} # current_retry_timeout

sub retry_timeout_backoff ($) {
  return $_[0]->{retry_timeout_backoff} || 'constant';
} # retry_timeout_backoff

sub _get_next_retry_timeout ($) {
  my $self = shift;
  my $method = $self->retry_timeout_backoff;
  return $BackoffAlgorithms->{$method}->('retry_timeout', $self);
} # _get_next_retry_timeout

sub elapsed_time ($) {
  return time - $_[0]->{start_time};
} # elapsed_time

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

$BackoffAlgorithms->{constant} = sub {
  my ($type, $timer) = @_;
  my $new = $timer->{"current_$type"};
  return defined $new ? $new : $timer->$type;
}; # constant
$BackoffAlgorithms->{exponential} = sub {
  my ($type, $timer) = @_;
  my $new = $timer->{"current_$type"};
  return $timer->$type unless defined $new;
  $new *= ($timer->{"$type\_backoff_multiplier"} || 1.5);
  my $max = $timer->{"$type\_backoff_max"} || 10;
  return $new < $max ? $new : $max;
}; # exponential
$BackoffAlgorithms->{random} = sub {
  my ($type, $timer) = @_;
  my $min = $timer->{"$type\_backoff_min"} || 1;
  my $max = $timer->{"$type\_backoff_max"} || 10;
  return rand ($max - $min) + $min;
}; # random

1;

=head1 LICENSE

Copyright 2012 Wakaba <wakaba@suikawiki.org>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
