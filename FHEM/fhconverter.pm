use strict;
use warnings;

package fronthem;
use Encode;

###############################################################################
#
# direkt relations (gadval == reading == setval)
#
###############################################################################
sub Direct(@)
{
  my ($param) = @_;
  my $cmd = $param->{cmd};
  my $gad = $param->{gad};
  my $gadval = $param->{gadval};

  my $device = $param->{device};
  my $reading = $param->{reading};
  my $event = $param->{event};
  
  my @args = @{$param->{args}};
  my $cache = $param->{cache};

  if ($param->{cmd} eq 'get')
  {
    $event = ($reading eq 'state')?main::Value($device):main::ReadingsVal($device, $reading, '');
    $param->{cmd} = 'send';
  }
  if ($param->{cmd} eq 'send')
  {
    $param->{gad} = $gad;
		$param->{gadval} = decode('utf-8', $event);
    #$param->{gadval} = $event;
		$param->{gads} = [];
    return undef;
  }
  elsif ($param->{cmd} eq 'rcv')
  {
		$param->{result} = $gadval;
		$param->{results} = [];
    return undef;
  }
  elsif ($param->{cmd} eq '?')
  {
    return 'usage: Direct';
  }
  return undef;
}

###############################################################################
#
# direct relations (gadval == reading == setval) 
# numerical, @param min and max 
#
###############################################################################
sub NumDirect(@)
{
  my ($param) = @_;
  my $cmd = $param->{cmd};
  my $gad = $param->{gad};
  my $gadval = $param->{gadval};

  my $device = $param->{device};
  my $reading = $param->{reading};
  my $event = $param->{event};
  
  my @args = @{$param->{args}};
  my $cache = $param->{cache};

  if ($param->{cmd} eq 'get')
  {
    $event = ($reading eq 'state')?main::Value($device):main::ReadingsVal($device, $reading, '');
    $param->{cmd} = 'send';
  }
  if ($param->{cmd} eq 'send')
  {
    $event =~ s/[^0-9.\-\+]//g;
    $param->{gad} = $gad;
    $param->{gadval} = $event;
    $param->{gads} = [];
    return undef;
  }
  elsif ($param->{cmd} eq 'rcv')
  {		
		my $min = $args[0];
		my $max = $args[1];
		my $adj = 0;
		$gadval =~ s/[^0-9.\-\+]//g;

		if (defined($min) && ($gadval < $min)) 
		{
      my $s = ($reading eq 'state')?'':$reading;
      $gadval = $min;
      main::fhem("trigger $device $s $gadval");
    }
		if (defined($max) && ($gadval > $max)) 
		{
      my $s = ($reading eq 'state')?'':$reading;
      $gadval = $max;
      main::fhem("trigger $device $s $gadval");
    }

	  $param->{result} = $gadval;
	  $param->{results} = [];
    return undef;
  }
  elsif ($param->{cmd} eq '?')
  {
    return 'usage: Direct';
  }
  return undef;
}

###############################################################################
#
# connect fhem device with on|off state to switch
#
###############################################################################
sub OnOff(@)
{
  my ($param) = @_;
  my $cmd = $param->{cmd};
  my $gad = $param->{gad};
  my $gadval = $param->{gadval};

  my $device = $param->{device};
  my $reading = $param->{reading};
  my $event = $param->{event};
  
  my @args = @{$param->{args}};
  my $cache = $param->{cache};

  if ($param->{cmd} eq 'get')
  {
    $event = ($reading eq 'state')?main::Value($device):main::ReadingsVal($device, $reading, 'off');
    $param->{cmd} = 'send';
  }
  if ($param->{cmd} eq 'send')
  {
    $param->{gad} = $gad;
		$param->{gadval} = (lc($event) eq 'on')?'1':'0';
		$param->{gads} = [];
    return undef;
  }
  elsif ($param->{cmd} eq 'rcv')
  {
		$param->{result} = ($gadval)?'on':'off';
		$param->{results} = [];
    return undef;
  }
  elsif ($param->{cmd} eq '?')
  {
    return 'usage: OnOff';
  }
  return undef;
}

###############################################################################
#
# numerical readings, one way fhem->fronthem
#
###############################################################################
sub NumDisplay(@)
{
  my ($param) = @_;
  my $cmd = $param->{cmd};
  my $gad = $param->{gad};
  my $gadval = $param->{gadval};

  my $device = $param->{device};
  my $reading = $param->{reading};
  my $event = $param->{event};
  
  my @args = @{$param->{args}};
  my $cache = $param->{cache};

  if ($param->{cmd} eq 'get')
  {
    $event = ($reading eq 'state')?main::Value($device):main::ReadingsVal($device, $reading, '0');
    $param->{cmd} = 'send';
  }
  if ($param->{cmd} eq 'send')
  {
    $param->{gad} = $gad;
		$event =~ /\D*([+-]{0,1}\d+[,.]{0,1}\d*).*/;
		my $format = (@args)?$args[0]:"%.1f";
		$param->{gadval} = sprintf($format, $1);
		#$param->{gadval} = sprintf("%.1f", $1);
		$param->{gads} = [];
    return undef;
  }
  elsif ($param->{cmd} eq 'rcv')
  {
    return 'done'; # only a display, no set
  }
  elsif ($param->{cmd} eq '?')
  {
    return 'usage: TBD!!!';
  }
  return undef;
}

###############################################################################
#
# RGB device, param: gad_r, gad_g, gad_b
# send: RGB HEX reading into three gad (r,g,b)
# rcv: 3 gad, serielized. Assembled to RGB HEX
#
###############################################################################
sub RGBCombined(@)
{
  my ($param) = @_;
  my $cmd = $param->{cmd};
  my $gad = $param->{gad};
  my $gadval = $param->{gadval};

  my $device = $param->{device};
  my $reading = $param->{reading};
  my $event = $param->{event};
  
  my @args = @{$param->{args}};
  my $cache = $param->{cache};

  return "error $gad: converter syntax: missing paramter" if (@args != 3);
  if ($param->{cmd} eq 'get')
  {
    $event = main::ReadingsVal($device, $reading, '000000');
    $param->{cmd} = 'send';
  }
  if ($param->{cmd} eq 'send')
  {
    return 'done' if ($gad ne $args[0]); #only one outgoing msg desired but we get triggered three times (each of r,g,b)
    push @{$param->{gads}}, ($args[0], hex substr($event, 0, 2), $args[1], hex substr($event, 2, 2), $args[2], hex substr($event, 4, 2));
    return undef;
  }
  elsif ($param->{cmd} eq 'rcv')
  {
    my $count = $cache->{$gad}->{count};
    foreach my $g (@args)
    {
      return 'done' if ($cache->{$g}->{count} != $count);
    }
    my $rgb = sprintf("%02x%02x%02x", $cache->{$args[0]}->{val}, $cache->{$args[1]}->{val}, $cache->{$args[2]}->{val});
    $param->{result} = $rgb;
    $param->{results} = [];
    return undef;
  }
  elsif ($param->{cmd} eq '?')
  {
    return 'usage: RGBCombined gad_r, gad_g, gad_b';
  }
  return undef;
}


1;
