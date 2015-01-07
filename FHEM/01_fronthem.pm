##############################################
# $Id: 01_fronthem.pm 0 2014-10-01 08:00:00Z herrmannj $

#TODO alot ;)
#organize loading order
#attr cfg file

# fixed:
# issue with some JSON module at startup
# perl before 5.14 issue 
# remove debug output

# open:
# UTF8 conversation 
# timestrings
# num converter with negative values
# 99er converter (see reload)

package main;

use strict;
use warnings;

use Socket;
use Fcntl;
use POSIX;
use IO::Socket;
use IO::Select;

use Net::WebSocket::Server;
use JSON;

use Data::Dumper;

sub
fronthem_Initialize(@)
{

  my ($hash) = @_;
  
  $hash->{DefFn}      = "fronthem_Define";
  $hash->{SetFn}      = "fronthem_Set";
  $hash->{ReadFn}     = "fronthem_Read";
  $hash->{UndefFn}    = "fronthem_Undef";
  $hash->{ShutdownFn} = "fronthem_Shutdown";
  $hash->{AttrList}   = "configFile ".$readingFnAttributes;
}

sub
fronthem_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $name = $a[0];
  my $cfg;

  $hash->{helper}->{COMMANDSET} = 'save';

  #TODO move it to "initialized"
  fronthem_ReadCfg($hash, 'fronthem.cfg');
  
  my $port = 16384;
  # create and register server ipc parent (listener == socket)
  do
  {
    $hash->{helper}->{listener} = IO::Socket::INET->new(
      LocalHost => 'localhost',
      LocalPort => $port, 
      Listen => 2, 
      Reuse => 1 );
    $port++;
  } until (defined($hash->{helper}->{listener}));
  $port -= 1;
  my $flags = fcntl($hash->{helper}->{listener}, F_GETFL, 0) or return "error shaping ipc: $!";
  fcntl($hash->{helper}->{listener}, F_SETFL, $flags | O_NONBLOCK) or return "error shaping ipc: $!";
  Log3 ($hash, 2, "$hash->{NAME}: ipc listener opened at port $port");
  $hash->{TCPDev} = $hash->{helper}->{listener};
  $hash->{FD} = $hash->{helper}->{listener}->fileno();
  $selectlist{"$name:ipcListener"} = $hash;

  $hash->{helper}->{main}->{state} = 'run';
  if ($init_done)
  {
    # TODO set initial readings
  }

  # prepare forking the ws server
  $cfg->{hash} = $hash;
  $cfg->{id} = 'ws';
  $cfg->{port} = 2121;
  $cfg->{ipcPort} = $port;
  fronthem_StartWebsocketServer($cfg);

  return undef;
}

sub
fronthem_Set(@)
{
  my ($hash, $name, $cmd, @args) = @_;
  my $cnt = @args;

  return "unknown command ($cmd): choose one of ".$hash->{helper}->{COMMANDSET} if not ( grep { $cmd eq $_ } split(" ", $hash->{helper}->{COMMANDSET} ));

  return fronthem_WriteCfg($hash) if ($cmd eq 'save');

  return undef;
}

#ipc, accept from forked socket server
sub 
fronthem_Read(@) 
{
  my ($hash) = @_;
  my $ipcClient = $hash->{helper}->{listener}->accept();
  my $flags = fcntl($ipcClient, F_GETFL, 0) or return "error shaping ipc client: $!";
  fcntl($ipcClient, F_SETFL, $flags | O_NONBLOCK) or return "error shaping ipc client: $!";

  # TODO connections from other then localhost possible||usefull ? evaluate the need ...
  
  my $ipcHash;
  $ipcHash->{TCPDev} = $ipcClient;
  $ipcHash->{FD} = $ipcClient->fileno();
  $ipcHash->{PARENT} = $hash;
  $ipcHash->{directReadFn} = \&fronthem_ipcRead;

  my $name = $hash->{NAME}.":".$ipcClient->peerhost().":".$ipcClient->peerport();
  $ipcHash->{NAME} = $name;
  $ipcHash->{TYPE} = "fronthem";
  $ipcHash->{buffer} = '';
  $selectlist{$name} = $ipcHash;

  # $hash->{helper}->{ipc}->{$name} = $ipcClient;
  # TODO log connection
  return undef;
}

sub 
fronthem_Notify($$)
{
  my ($hash, $ntfyDev) = @_;
  my $ntfyDevName = $ntfyDev->{NAME};

  # responde to fhem system events
  # INITIALIZED|REREADCFG|DEFINED|RENAMED|SHUTDOWN
  if ($ntfyDevName eq "global")
  {
    foreach my $event (@{$ntfyDev->{CHANGED}})
    {
      my @e = split(' ', $event);
      Log3 ($hash, 1, "in $e[0]"); #TODO remove
      if ($e[0] eq 'INITIALIZED')
      {
        #
      }
      elsif ($e[0] eq 'RENAMED')
      {
        # is it a child device ?
        # if ($gateway && ($gateway->{NAME} eq $e[1]))
        # {
        #  Log3 ($hash, 4, "$hash->{NAME}:gatway $e[1] renamed to $e[2] - update settings");
        # }
      }
    }
  }
  return undef;
}

sub
fronthem_Undef(@)
{
  my ($hash) = @_;
  Log3 ($hash, 4, "$hash->{NAME}: undef called");
  $hash->{helper}->{main}->{state} = 'undef';
  $hash->{helper}->{ipc}->{'ws'}->{sock}->{TCPDev}->close();
  return undef;
}

sub
fronthem_Shutdown(@)
{
  my ($hash) = @_;
  Log3 ($hash, 4, "$hash->{NAME}: shutdown called");
  $hash->{helper}->{main}->{state} = 'shutdown';
  return undef;
}

#ipc, read msg from forked socket server
sub 
fronthem_ipcRead($) 
{
  my ($ipcHash) = @_;
  my $msg = "";
  my ($up, $rv);
  my ($id,$pid) = ('?','?');

  my $knownThreadId = (defined($ipcHash->{registered}))?$ipcHash->{registered}:'?';

  $rv = $ipcHash->{TCPDev}->recv($msg, POSIX::BUFSIZ, 0);
  unless (defined($rv) && length $msg) {
    # child is termitating ...
    # clean exit
    return undef if ($ipcHash->{PARENT}->{helper}->{main}->{state} ne 'run');
    Log3 ($ipcHash->{PARENT}, 1, "$ipcHash->{PARENT}->{NAME}: thread $knownThreadId closed for unknown reason");
    delete $selectlist{$ipcHash->{NAME}};
    $ipcHash->{TCPDev}->close();
    delete $ipcHash->{PARENT}->{helper}->{ipc}->{$ipcHash->{NAME}};
    # TODO set state
    # see who is using it and unregister
    # TODO add (wss, plot) if available
    if ($knownThreadId eq 'ws')
    {
      foreach my $key (keys %{$ipcHash->{PARENT}->{helper}->{sender}})
      {
        if ($ipcHash->{PARENT}->{helper}->{sender}->{$key}->{connection} eq $knownThreadId)
        {
          # disconnect fronthemClient
          # TODO 
        }
      }
    }
    # TODO restart
    return undef;
  }

  $ipcHash->{buffer} .= $msg;

  while (($ipcHash->{buffer} =~ m/\n/) && (($msg, $ipcHash->{buffer}) = split /\n/, $ipcHash->{buffer}, 2))
  {
    Log3 ($ipcHash->{PARENT}, 5, "ipc $ipcHash->{NAME} ($knownThreadId): receive $msg");

    if (defined($ipcHash->{registered}))
    {
      $id = $ipcHash->{registered}; 
      # TODO check if a dispatcher is set
      eval 
      {
        $up = decode_json($msg);
        Log3 ($ipcHash->{PARENT}, $up->{log}->{level}, "ipc $ipcHash->{NAME} ($id): $up->{log}->{text}") if (exists($up->{log}) && (($up->{log}->{cmd} || '') eq 'log'));
        #keep cfg up to date
        if (exists($up->{message}) && (($up->{message}->{cmd} || '') eq 'monitor'))
        {
          foreach my $item (@{$up->{message}->{items}})
          {
            $ipcHash->{PARENT}->{helper}->{config}->{$item}->{type} = 'item' unless defined($ipcHash->{PARENT}->{helper}->{config}->{$item}->{type});
          }
        }
        if (exists($up->{message}) && (($up->{message}->{cmd} || '') eq 'series'))
        {
          my $item = $up->{message}->{item};
          $ipcHash->{PARENT}->{helper}->{config}->{$item}->{type} = 'plot';
        }
        fronthem_ProcessDeviceMsg($ipcHash, $up) if (exists($up->{message}));
        1;
      } or do {
        my $e = $@;
        Log3 ($ipcHash->{PARENT}, 2, "ipc $ipcHash->{NAME} ($id): error $e decoding ipc msg $msg");
      }
    }
    else
    {
      # first incoming msg, must contain id:pid (name) of forked child
      # security check, see if we are waiting for. id and pid should be registered in $hash->{helper}->{ipc}->{$id}->{pid} before incoming will be accepted 
      if (($msg =~ m/^(\w+):(\d+)$/) && ($ipcHash->{PARENT}->{helper}->{ipc}->{$1}->{pid} eq $2))
      {
        ($id,$pid) = ($1, $2);
        # registered: set id if recognized
        $ipcHash->{registered} = $id;
        # sock: how to talk to client process
        $ipcHash->{PARENT}->{helper}->{ipc}->{$id}->{sock} = $ipcHash;
        # name: how selectlist name it
        $ipcHash->{PARENT}->{helper}->{ipc}->{$id}->{name} = $ipcHash->{NAME};
      }
      else
      {
        #security breach: unexpected incoming (child?) connection
        Log3 ($ipcHash->{PARENT}, 2, "$id unexpected incoming connection $msg");
      }
    }
  }
  return undef;
}

# TODO remove, not used anymore
# id: ..name of process (ie ws), $msg: what to tell
sub 
fronthem_ipcWrite(@)
{
  my ($hash,$id,$msg) = @_;
  my $result = $hash->{helper}->{ipc}->{$id}->{sock}->send(encode_json($msg)."\n", 0);  
  return undef;
}

sub
fronthem_RegisterClient(@)
{
  my ($hash, $client) = @_;
  $hash->{helper}->{client}->{$client} = 'registered';
  return undef;
}

sub
fronthem_ReadCfg(@)
{
  my ($hash) = @_;
  my $cfgFile = AttrVal($hash->{NAME}, 'configFile', "fhserver.$hash->{NAME}.cfg");
  $cfgFile = "./www/fronthem/server/$hash->{NAME}/$cfgFile";

  my $json_text = '';
  my $json_fh;
  open($json_fh, "<:encoding(UTF-8)", $cfgFile) and do
  {
    #Log3 ($hash, 1, "$hash->{NAME}: Error loading cfg file $!");
    local $/;
    $json_text = <$json_fh>;
    close $json_fh;
  };

  my $data;
  my $filtered->{config} = {};
  
  if (length($json_text))
  {
    eval 
    {
      my $json = JSON->new->utf8;
      $data = $json->decode($json_text);
    };
    if ($@)
    {
      Log3 ($hash, 1, "$hash->{NAME}: Error loading cfg file $@");
      $data->{config} = {};
    }

    #TODO keep filter logic up-to-date

    foreach my $key (keys %{$data->{config}})
    {
      $filtered->{config}->{$key}->{type} = $data->{config}->{$key}->{type};
      $filtered->{config}->{$key}->{device} = $data->{config}->{$key}->{device};
      $filtered->{config}->{$key}->{reading} = $data->{config}->{$key}->{reading};
      $filtered->{config}->{$key}->{converter} = $data->{config}->{$key}->{converter};
      $filtered->{config}->{$key}->{set} = $data->{config}->{$key}->{set};
    }
  }

  $hash->{helper}->{config} = $filtered->{config};
  fronthem_CreateListen($hash);
  return undef;
}

sub
fronthem_WriteCfg(@)
{
  my ($hash) = @_;
  my $cfgContent;
  my $cfgFile = AttrVal($hash->{NAME}, 'configFile', "fhserver.$hash->{NAME}.cfg");

  $cfgContent->{version} = '1.0';
  $cfgContent->{modul} = 'fronthem-server';
  
  foreach my $key (keys %{ $hash->{helper}->{config} })
  {
    if ($hash->{helper}->{config}->{$key}->{type} eq 'item')
    {
      $cfgContent->{config}->{$key}->{type} = $hash->{helper}->{config}->{$key}->{type};
      $cfgContent->{config}->{$key}->{device} = $hash->{helper}->{config}->{$key}->{device};
      $cfgContent->{config}->{$key}->{reading} = $hash->{helper}->{config}->{$key}->{reading};
      $cfgContent->{config}->{$key}->{converter} = $hash->{helper}->{config}->{$key}->{converter};
      $cfgContent->{config}->{$key}->{set} = $hash->{helper}->{config}->{$key}->{set};
    }
  }

  mkdir('./www/fronthem',0777) unless (-d './www/fronthem');
  mkdir('./www/fronthem/server',0777) unless (-d './www/fronthem/server');
  mkdir("./www/fronthem/server/$hash->{NAME}",0777) unless (-d "./www/fronthem/server/$hash->{NAME}");

  $cfgFile = "./www/fronthem/server/$hash->{NAME}/$cfgFile";

  my $cfgOut = JSON->new->utf8;
  open (my $cfgHandle, ">:encoding(UTF-8)", $cfgFile);
  print $cfgHandle $cfgOut->pretty->encode($cfgContent);
  close $cfgHandle;;

  fronthem_CreateListen($hash);
  return undef;
}

sub
fronthem_CreateListen(@)
{
  my ($hash) = @_;
  my $listen;

  foreach my $key (keys %{$hash->{helper}->{config}})
  {
    my $gad = $hash->{helper}->{config}->{$key};
    $listen->{$gad->{device}}->{$gad->{reading}}->{$key} = $hash->{helper}->{config}->{$key} if ((defined($gad->{device})) && (defined($gad->{reading})));
  }
  $hash->{helper}->{listen} = $listen;
  return undef;
}

###############################################################################
#
# main device (parent)
# decoding utils
#
# $msg is hash: the former client json plus ws server enrichment data (sender ip, identity, timestamp)

sub
fronthem_ProcessDeviceMsg(@)
{
  my ($ipcHash, $msg) = @_;

  my $hash = $ipcHash->{PARENT};  

  my $connection = $ipcHash->{registered}.':'.$msg->{'connection'};
  my $sender = $msg->{'sender'};
  my $identity = $msg->{'identity'};
  my $message = $msg->{'message'};
  
  #TODO: 
  # check if device with given identity is already connected
  # if so, reject the connection and give it a hint why

  #check if conn is actual know
  if (!defined $hash->{helper}->{receiver}->{$connection})
  {
    if (($message->{cmd} || '') eq 'connect')
    {
      $hash->{helper}->{receiver}->{$connection}->{sender} = $sender;
      $hash->{helper}->{receiver}->{$connection}->{identity} = $identity;
      $hash->{helper}->{receiver}->{$connection}->{state} = 'connecting';
    }
    else
    {
      #TODO error logging, disconnect 
    }
  }
  elsif((($message->{cmd} || '') eq 'handshake') && ($hash->{helper}->{receiver}->{$connection}->{state} eq 'connecting') )
  {
    my $access = $msg->{sender};

    foreach my $key (keys %defs)
    {
      if (($defs{$key}{TYPE} eq 'fronthemDevice') && (ReadingsVal($key, 'identity', '') eq $access))
      {
        $hash->{helper}->{receiver}->{$connection}->{device} = $key;
        $hash->{helper}->{receiver}->{$connection}->{state} = 'connected';
        #build sender 
        $hash->{helper}->{sender}->{$key}->{connection} = $ipcHash->{registered};
        $hash->{helper}->{sender}->{$key}->{ressource} = $msg->{'connection'};
        $hash->{helper}->{sender}->{$key}->{state} = 'connected';
      }
    }
    # sender could not be confirmed, put it on-hold because it may be defined later
    if ($hash->{helper}->{receiver}->{$connection}->{state} eq 'connecting')
    {
      $hash->{helper}->{receiver}->{$connection}->{state} = 'rejected';
      readingsSingleUpdate($hash, 'lastError', "client $access rejected", 1);
      Log3 ($ipcHash->{PARENT}, 2, "$ipcHash->{PARENT}->{NAME} $ipcHash->{NAME} ($ipcHash->{registered}): client $access rejected");
    }
  }
  elsif(($message->{cmd} || '') eq 'handshake')
  {
    #TODO handshake out of of sync, not really sure whats to do
  }
  elsif($hash->{helper}->{receiver}->{$connection}->{state} eq 'rejected')
  {
    my $access = $msg->{sender};

    #TODO check registered device only
    foreach my $key (keys %defs)
    {
      if (($defs{$key}{TYPE} eq 'fronthemDevice') && (ReadingsVal($key, 'identity', '') eq $access))
      {
        $hash->{helper}->{receiver}->{$connection}->{device} = $key;
        $hash->{helper}->{receiver}->{$connection}->{state} = 'connected';
        #build sender 
        $hash->{helper}->{sender}->{$key}->{connection} = $ipcHash->{registered};
        $hash->{helper}->{sender}->{$key}->{ressource} = $msg->{'connection'};
        $hash->{helper}->{sender}->{$key}->{state} = 'connected';
        #set state
      }
    }
  }
  
  if(($message->{cmd} || '') eq 'disconnect') 
  {
    my $key = $hash->{helper}->{receiver}->{$connection}->{device};

    delete($hash->{helper}->{receiver}->{$connection});
    if ($key)
    {
      my $devHash = $defs{$key};
      fronthemDevice_fromDriver($devHash, $msg);
      delete($hash->{helper}->{sender}->{$key});  
    }  
    return undef;
  }

  return undef if(($hash->{helper}->{receiver}->{$connection}->{state} || '') ne 'connected');
  #dispatch to device
  my $key = $hash->{helper}->{receiver}->{$connection}->{device};
  my $devHash = $defs{$key};
  fronthemDevice_fromDriver($devHash, $msg);

  return undef;
}

#device = name of fhem instance of fronthemDevice
#msg is hash from fhem fronthemDevice instance, will be dispatched to forked client, an further to sv client
#msg->receiver = speaking name (eg tab)
#msg->ressource
#msg->message->cmd 
sub
fronthem_FromDevice(@)
{
  # TODO
  # only write if ipc instance is available
  # (if not: lg warning, disconnect device)
  # write at ipc write

  my ($hash, $device, $msg) = @_;
  #connection as ipc instance
  my $connection = $hash->{helper}->{sender}->{$device}->{connection};
  #ressource within ipc child, leave blank if you want t talk with the process itself
  $msg->{ressource} = $hash->{helper}->{sender}->{$device}->{ressource};
  $hash->{helper}->{ipc}->{$connection}->{sock}->{TCPDev}->send(encode_json($msg)."\n", 0);
  return undef;  
}

###############################################################################
#
# forked child ahaed

sub
fronthem_StartWebsocketServer(@)
{
  my ($cfg) = @_;  
  my $id = $cfg->{id};

  my $pid = fork();
  return "Error while try to fork $id: $!" unless (defined $pid);

  if ($pid)
  {
    # prepare parent for incoming connection
    $cfg->{hash}->{helper}->{ipc}->{$id}->{pid} = $pid;
    return undef;
  }

  # child ahead
  setsid();

  # close open handles
  close STDOUT;  
  open STDOUT, '>/dev/null';
  close STDIN;
  close STDERR;  
  open STDOUT, '>/dev/null';

  foreach my $key (keys %defs) { TcpServer_Close($defs{$key}) if ($defs{$key}->{SERVERSOCKET}); }
  foreach my $key (keys %selectlist) { POSIX::close ($selectlist{$key}->{FD}) if (defined($selectlist{$key}->{FD})); }

  # connect to main process
  my $ipc = new IO::Socket::INET (
    PeerHost => 'localhost',
    PeerPort => $cfg->{ipcPort},
    Proto => 'tcp'
  );
  #announce my name
  Log3 ($cfg->{hash}->{NAME}, 3, "IN CHILD start forked $id: $id:$$");
  $ipc->send("$id:$$\n", 0);
  fronthem_forkLog3($ipc, 3, "$id alive with pid $$");

  my $server = new IO::Socket::INET (
    Listen => SOMAXCONN,
    LocalPort => $cfg->{port},
    Proto => 'tcp',
    Reuse => 1
  );
  # my $flags = fcntl($server, F_GETFL, 0);
  # fcntl($server, F_SETFL, $flags | O_NONBLOCK);

  my $ws = Net::WebSocket::Server->new(
    listen => $server,
    on_connect => \&fronthem_wsConnect
  );
  $ws->{'ipc'} = $ipc;
  $ws->{id} = $id;
  $ws->{buffer} = '';
  $ws->watch_readable($ipc->fileno() => \&fronthem_wsIpcRead);
  $ws->start;
  POSIX::_exit(0);
}

sub
fronthem_forkLog3(@)
{
  my ($ipc, $level, $text) = @_;
  my $msg;
  $msg->{log}->{cmd} = 'log';
  $msg->{log}->{level} = $level;
  $msg->{log}->{text} = $text;
  $ipc->send(encode_json($msg)."\n", 0);
  return undef;
}

sub
fronthem_wsConnect(@)
{
  my ($serv, $conn) = @_;

  my $flags = fcntl($conn->socket(), F_GETFL, 0);
  fcntl($conn->socket(), F_SETFL, $flags | O_NONBLOCK);

  $conn->on(
    handshake => \&fronthem_wsHandshake,
    utf8 => \&fronthem_wsUtf8,
    disconnect => \&fronthem_wsDisconnect
  );
  my @chars = ("A".."Z", "a".."z","0".."9");
  my $cName = "conn-";
  $cName .= $chars[rand @chars] for 1..8;
  my $senderIP = $conn->ip();
  my $msg = "{\"connection\":\"$cName\",\"sender\":\"$senderIP\",\"identity\":\"unknown\",\"message\":{\"cmd\":\"connect\"}}";
  my $size = $conn->server()->{ipc}->send($msg."\n",0);
  $conn->{id} = $cName;
  $serv->{$cName} = $conn;
  return undef;
}

sub
fronthem_wsHandshake(@)
{
  my ($conn, $handshake) = @_;
  my $senderIP = $conn->ip();
  my $cName = $conn->{id};
  my $msg = "{\"connection\":\"$cName\",\"sender\":\"$senderIP\",\"identity\":\"unknown\",\"message\":{\"cmd\":\"handshake\"}}";
  my $size = $conn->server()->{ipc}->send($msg."\n",0);
  return undef;
}

sub
fronthem_wsUtf8(@)
{
  my ($conn, $msg) = @_;
  my $senderIP = $conn->ip();
  my $cName = $conn->{id};
  #add header
  $msg =~ s/^{/{"connection":"$cName","sender":"$senderIP","identity":"unknown", "message":{/g;
  $msg .= "}";
  my $size = $conn->server()->{ipc}->send($msg."\n",0);
  return undef;
}

#http://tools.ietf.org/html/rfc6455#section-7.4.1
sub
fronthem_wsDisconnect(@)
{
  my ($conn, $code, $reason) = @_;
  $code = 0 unless(defined($code));
  $reason = 0 unless(defined($reason));
  my $senderIP = $conn->ip();
  my $cName = $conn->{id};
  #add header
  my $msg = "{\"connection\":\"$cName\",\"sender\":\"$senderIP\",\"identity\":\"unknown\",\"message\":{\"cmd\":\"disconnect\"}}";
  my $size = $conn->server()->{ipc}->send($msg."\n",0);
  return undef;
}


# main interface for all msg from main thread (here designated to ws)
sub
fronthem_wsIpcRead(@)
{
  my ($serv, $fh) = @_;
  my $msg = '';
  my $rv;
  
  $rv = $serv->{'ipc'}->recv($msg, POSIX::BUFSIZ, 0);
  unless (defined($rv) && length $msg) {
    $serv -> shutdown();
    return undef;
  }
  $serv->{buffer} .= $msg;
  while (($serv->{buffer} =~ m/\n/) && (($msg, $serv->{buffer}) = split /\n/, $serv->{buffer}, 2))
  {
    $msg = decode_json($msg);
    fronthem_wsProcessInboundCmd($serv, $msg);
  }
  return undef;
}

#msg->receiver = speaking name (eg tab)
#msg->ressource
#msg->message->cmd 

sub
fronthem_wsProcessInboundCmd(@)
{
  my ($serv, $msg) = @_;
  fronthem_forkLog3 ($serv->{ipc}, 4, "$serv->{id} send to client".encode_json($msg->{message}));
  foreach my $conn ($serv->connections())
  {
    if ($conn->{id} eq $msg->{ressource})
    {
      return fronthem_forkLog3 ($serv->{ipc}, 1, "$serv->{id} found a closed socket for $msg->{receiver}") unless $conn->socket();
      unless (IO::Select->new($conn->socket())->can_write(0))
      {
        $conn->disconnect(1011, '');
        return fronthem_forkLog3 ($serv->{ipc}, 3, "$serv->{id} force disconnect for $msg->{receiver}");
      } 
      $conn->send_utf8(encode_json($msg->{message})) if ($conn->{id} eq $msg->{ressource});
    }
  }
  return undef;
}

1;

