##############################################
# $Id: 99_fronthemUtils.pm 0 2015-11-10 08:00:00Z herrmannj $
package main;

use strict;
use warnings;

sub
fronthemUtils_Initialize($$)
{
  my ($hash) = @_;
}

package fronthem;
use strict;
use warnings;

###############################################################################
#
# connect fhem device with on|off state to switch
#
###############################################################################
sub AnAus(@)
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
    $event = ($reading eq 'state')?main::Value($device):main::ReadingsVal($device, $reading, 'aus');
    $param->{cmd} = 'send';
  }
  if ($param->{cmd} eq 'send')
  {
    $param->{gad} = $gad;
		$param->{gadval} = (lc($event) eq 'an')?'1':'0';
		$param->{gads} = [];
    return undef;
  }
  elsif ($param->{cmd} eq 'rcv')
  {
		$param->{result} = ($gadval)?'an':'aus';
		$param->{results} = [];
    return undef;
  }
  elsif ($param->{cmd} eq '?')
  {
    return 'usage: AnAus';
  }
  return undef;
}



1;

=pod
=begin html

<a name="fronthemUtils"></a>
<h3>fronthemUtils</h3>
<ul>
</ul>
=end html
=cut
