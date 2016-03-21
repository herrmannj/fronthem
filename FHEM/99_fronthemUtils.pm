##############################################
# $Id: 99_fronthemUtils.pm 0 2015-11-10 08:00:00Z herrmannj $
package main;

use strict;
use warnings;
use JSON;

sub
fronthemUtils_Initialize($$)
{
  my ($hash) = @_;
}

sub fronthem_decodejson($) {
 return decode_json($_[0]);
}  

sub fronthem_encodejson($) {
 return encode_json($_[0]);
}  


###############################################################################
#
# Umsetzen der UZSU-Settings für ein device
#
###############################################################################
sub UZSU_execute($$)
{
 my ($device, $uzsu) = @_;
 my $weekdays = "";
 my $perlString = "";
 
 $uzsu = decode_json($uzsu);

 fhem('delete wdt_uzsu_'.$device.'.*');
 
 for(my $i=0; $i < @{$uzsu->{list}}; $i++) {
     $weekdays = $uzsu->{list}[$i]->{rrule};
     $weekdays = substr($weekdays,18,50);

     # if the structure contains the holidays list, use it!
     if ($uzsu->{list}[$i]->{holiday}->{weekend}) {
	if ($weekdays ne '') {
		$weekdays = $weekdays . ',';
	}
     	$weekdays = $weekdays . '$we';
     }
     if ($uzsu->{list}[$i]->{holiday}->{work}) {
	if ($weekdays ne '') {
		$weekdays = $weekdays . ',';
	}
     	$weekdays = $weekdays . '!$we';
     }
     
     if ($uzsu->{list}[$i]->{event} eq 'time'){
         $weekdays = $weekdays.'|'.$uzsu->{list}[$i]->{time}.'|'.$uzsu->{list}[$i]->{value};
     } else {
         # Bugfix below: because sunset_abs from 99_sunrise_el does not work if max-time = ""
         if ($uzsu->{list}[$i]->{timeMin} ne '' and $uzsu->{list}[$i]->{timeMax} ne '') {
             $weekdays = $weekdays.'|{'.$uzsu->{list}[$i]->{event}.'_abs("REAL",'.$uzsu->{list}[$i]->{timeOffset} * 60 .',"'.$uzsu->{list}[$i]->{timeMin}.'","'.$uzsu->{list}[$i]->{timeMax}.'")}|'.$uzsu->{list}[$i]->{value};
         } else {
             $weekdays = $weekdays.'|{'.$uzsu->{list}[$i]->{event}.'_abs("REAL",'.$uzsu->{list}[$i]->{timeOffset} * 60 .',,)}|'.$uzsu->{list}[$i]->{value};
         }
     }
     
     # if the structure contains a condition, use it!
	 if ($uzsu->{list}[$i]->{condition}->{conditionActive}) {
	    if ($uzsu->{list}[$i]->{condition}->{conditionType} eq 'Perl') {
		    print 'Perl-Condition\n';
		    $perlString = $uzsu->{list}[$i]->{condition}->{conditionDevicePerl};
			print $perlString;
			#$perlString =~ s/\\"/"/ig;
			#print $perlString;
     		$weekdays = $weekdays.' ('.$perlString.')';
			print $weekdays;
     	} else {
		    print 'non-Perl-Condition\n';
     		$weekdays = $weekdays.' (ReadingsVal("'.$uzsu->{list}[$i]->{condition}->{conditionDevicePerl}.'","state","") '.$uzsu->{list}[$i]->{condition}->{conditionType}.' "'.$uzsu->{list}[$i]->{condition}->{conditionValue}.'")';
     	}
     }

     if ($uzsu->{list}[$i]->{active}){
         fhem('defmod wdt_uzsu_'.$device.'_'.$i.' WeekdayTimer '.$device.' en '.$weekdays);
         fhem('attr wdt_uzsu_'.$device.'_'.$i.' room UZSU');
         fhem('attr wdt_uzsu_'.$device.'_'.$i.' group '.$device);
     }
     #fhem('save');   # use only if you want to save WDT settings immediately.
 }
}

package fronthem;
use strict;
use warnings;

###############################################################################
# For use with UZSU-Widget in SV and UZSU-notify in fhem
# Setreading a device reading using JSON conversion (gadval => reading=decode_json() => setval => encode_json(reading) )
# the reading ("uzsu") must be created manually for each UZSU-enabled device in fhem using "setreading <device> uzsu {}"
# in the fhem commandline
###############################################################################

sub UZSU(@)
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
    $param->{cmd} = 'send';
  }
  if ($param->{cmd} eq 'send')
  {
    $param->{gad} = $gad;
	$param->{gadval} = main::fronthem_decodejson(main::ReadingsVal($device, $reading, '{}'));
	$param->{gads} = [];
    return undef;
  }
  elsif ($param->{cmd} eq 'rcv')
  {
	$gadval = main::fronthem_encodejson($gadval);
	main::UZSU_execute($device, $gadval);
	$gadval =~ s/;/;;/ig;
	$param->{result} = main::fhem("setreading $device $reading $gadval");
	$param->{results} = [];
    return 'done';
  }
  elsif ($param->{cmd} eq '?')
  {
    return 'usage: UZSU';
  }
  return undef;
}

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
