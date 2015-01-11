##############################################
# $Id: fhwebsocket.pm 0 2015-01-09 08:00:00Z herrmannj $
#
# rewrite to support full non-blocking mode, therefore set to default
# by Joerg Herrmann 2015
#
# based on
# Net::WebSocket::Server 
# Net::WebSocket::Server::Connection
# by Eric Wastl.
# 
# This program is free software; you can redistribute it and/or modify it
# under the terms of the the Artistic License (2.0). You may obtain a
# copy of the full license at:
# http://www.perlfoundation.org/artistic_license_2_0
#
# This program is part of fhem under GPL license
#


package fronthem::Websocket::Server;

use Carp;
use IO::Socket::INET;
use IO::Select;
use Net::WebSocket::Server::Connection;
use Time::HiRes qw(time);
use List::Util qw(min);

use Net::WebSocket::Server;
our @ISA = qw(Net::WebSocket::Server);

sub start {
  my $self = shift;

  # if we merely got a port, set up a reasonable default tcp server
  $self->{listen} = IO::Socket::INET->new(
    Listen    => 5,
    LocalPort => $self->{listen},
    Proto     => 'tcp',
    ReuseAddr => 1,
  ) || croak "failed to listen on port $self->{listen}: $!" unless ref $self->{listen};

  $self->{select_readable}->add($self->{listen});

  $self->{conns} = {};
  my $silence_nextcheck = $self->{silence_max} ? (time + $self->{silence_checkinterval}) : 0;
  my $tick_next = $self->{tick_period} ? (time + $self->{tick_period}) : 0;

  while (%{$self->{conns}} || $self->{listen}->opened) {
    my $silence_checktimeout = $self->{silence_max} ? ($silence_nextcheck - time) : undef;
    my $tick_timeout = $self->{tick_period} ? ($tick_next - time) : undef;
    my $timeout = min(grep {defined} ($silence_checktimeout, $tick_timeout));

    my ($ready_read, $ready_write, undef) = IO::Select->select($self->{select_readable}, $self->{select_writable}, undef, $timeout);
    foreach my $fh ($ready_read ? @$ready_read : ()) {
      if ($fh == $self->{listen}) {
        my $sock = $self->{listen}->accept;
        next unless $sock;
        my $conn = new fronthem::WebSocket::Server::Connection(socket => $sock, server => $self); # TODO replace to upgrade for nonblocking
        $conn->{writebuffer} = ''; # TODO move to constructor of connection
        $self->{conns}{$sock} = {conn=>$conn, lastrecv=>time};
        $self->{select_readable}->add($sock);
        $self->{on_connect}($self, $conn);
      } elsif ($self->{watch_readable}{$fh}) {
        $self->{watch_readable}{$fh}{cb}($self, $fh);
      } elsif ($self->{conns}{$fh}) {
        my $connmeta = $self->{conns}{$fh};
        $connmeta->{lastrecv} = time;
        $connmeta->{conn}->recv();
      } else {
        warn "filehandle $fh became readable, but no handler took responsibility for it; removing it";
        $self->{select_readable}->remove($fh);
      }
    }

    foreach my $fh ($ready_write ? @$ready_write : ()) {
      if ($self->{watch_writable}{$fh}) {
        $self->{watch_writable}{$fh}{cb}($self, $fh);
      } elsif ($self->{conns}{$fh}) {
        my $connmeta = $self->{conns}{$fh};
        $connmeta->{lastwrite} = time;
        $connmeta->{conn}->writeout();
      } else {
        warn "filehandle $fh became writable, but no handler took responsibility for it; removing it";
        $self->{select_writable}->remove($fh);
      }
    }

    if ($self->{silence_max}) {
      my $now = time;
      if ($silence_nextcheck < $now) {
        my $lastcheck = $silence_nextcheck - $self->{silence_checkinterval};
        $_->{conn}->send('ping') for grep { $_->{lastrecv} < $lastcheck } values %{$self->{conns}};

        $silence_nextcheck = $now + $self->{silence_checkinterval};
      }
    }

    if ($self->{tick_period} && $tick_next < time) {
      $self->{on_tick}($self);
      $tick_next += $self->{tick_period};
    }
  }
}

package fronthem::WebSocket::Server::Connection;

use 5.006;
use strict;
use warnings FATAL => 'all';

use Carp;
use Protocol::WebSocket::Handshake::Server;
use Protocol::WebSocket::Frame;
use Socket qw(IPPROTO_TCP TCP_NODELAY);
use Encode;

use Time::HiRes qw(time);

use Net::WebSocket::Server::Connection;
our @ISA = qw(Net::WebSocket::Server::Connection);

sub send {
  my ($self, $type, $data) = @_;

local $| = 1;

  if ($self->{handshake}) {
    carp "tried to send data before finishing handshake";
    return 0;
  }

  my $frame = new Protocol::WebSocket::Frame(type => $type, max_payload_size => $self->{max_send_size});
  $frame->append($data) if defined $data;

  my $bytes = eval { $frame->to_bytes };
  if (!defined $bytes) {
    carp "error while building message: $@" if $@;
    return;
  }
  $self->write($bytes);
}

sub write {
  my ($self, $bytes) = @_;
  my $fill = length $self->{writebuffer};
  $self->{writebuffer} .= $bytes;
  return if $fill;
  $self->writeout();
}

sub writeout {
  my ($self) = @_;
  # TODO why ? return unless $self->{writebuffer}; 
  my $num = syswrite($self->{socket}, $self->{writebuffer});
  # nothing written for unkown reason, stay tuned 
  return unless (defined $num);
  if ($num == length $self->{writebuffer} || $! == POSIX::EWOULDBLOCK) {
    substr ($self->{writebuffer}, 0, $num) = '';
    # clear or set select
    if (length $self->{writebuffer}) {
      $self->{select_writable}->add($self->{socket}) unless exists $self->{select_writable}->{$self->{socket}};
    } else {
      $self->{select_writable}->remove($self->{socket}) if exists $self->{select_writable}->{$self->{socket}};
    }
  } # TODO else { something went wrong, close connection } 
}

sub recv {
  my ($self) = @_;

  my ($len, $data) = (0, "");
  if (!($len = sysread($self->{socket}, $data, 8192))) {
    $self->disconnect();
    return;
  }

  # read remaining data
  $len = sysread($self->{socket}, $data, 8192, length($data)) while $len >= 8192;

  if ($self->{handshake}) {
    $self->{handshake}->parse($data);
    if ($self->{handshake}->error) {
      $self->disconnect(1002);
    } elsif ($self->{handshake}->is_done) {
      $self->_event(on_handshake => $self->{handshake});
      return unless do { local $SIG{__WARN__} = sub{}; $self->{socket}->connected };

      syswrite($self->{socket}, $self->{handshake}->to_string);
      delete $self->{handshake};

      $self->{parser} = new Protocol::WebSocket::Frame();
      setsockopt($self->{socket}, IPPROTO_TCP, TCP_NODELAY, 1) if $self->{nodelay};
      $self->_event('on_ready');
    }
    return;
  }

  $self->{parser}->append($data);

  my $bytes;
  while (defined ($bytes = eval { $self->{parser}->next_bytes })) {
    if ($self->{parser}->is_binary) {
      $self->_event(on_binary => $bytes);
    } elsif ($self->{parser}->is_text) {
      $self->_event(on_utf8 => Encode::decode('UTF-8', $bytes));
    } elsif ($self->{parser}->is_pong) {
      $self->_event(on_pong => $bytes);
    } elsif ($self->{parser}->is_close) {
      $self->disconnect(length $bytes ? unpack("na*",$bytes) : ());
      return;
    }
  }

  if ($@) {
    $self->disconnect(1002);
    return;
  }
}


1;
