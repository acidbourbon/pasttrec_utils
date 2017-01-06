#!/usr/bin/perl

use strict;
use warnings;
use feature 'state';
use URI::Escape;
use Data::Dumper;
#use HADES::TrbNet;
use Time::HiRes qw( usleep);
use Getopt::Long;
use Fcntl;


my @counters;  
my $port;
my $help;
my $ser_dev;
my $isTrbNet = 0;
my $poll = 0;
my $cmd = "";
my $verbose = 0;
my $invert_trigger = 0;
my $timing_reference = 8;
my $disable_mask = "0";

my $fh;

Getopt::Long::Configure(qw(gnu_getopt));
GetOptions(
           'help|h' => \$help,
           'device|d=s' => \$ser_dev,
           'disable_mask|m=s' => \$disable_mask,
           'poll|p' => \$poll,
           'verbose|v' => \$verbose,
           'invert_trigger|i' => \$invert_trigger,
           'tref_chan|t=s' => \$timing_reference,
          ) ;

if ($help || (defined $ARGV[0] && $ARGV[0] =~ /help/)) {
  exit;
  }
          
          
$ser_dev = "/dev/ttyUSB0" unless defined $ser_dev;
$cmd = "RD0" if $poll;
my $last = 0;


my $c = "stty -F $ser_dev 921600 raw";
#my $c = "stty -F $ser_dev -isig -icanon -iexten speed 921600 time 100";
my $r = qx($c);
print $r;

$r = open ($fh, "+<", $ser_dev);
unless ($fh) {
  print "can't open serial interface $ser_dev\n";
  exit;
}

$|=1;

#my $ff; 
#open($ff, "<", "delme");


sub Stream {
  my $v = 0;
  my $e = 0;
#   my $wordcount = -1100;
  
  # emptying buffers for 2 seconds 
  eval { 
    local $SIG{ALRM} = sub { die "alarm clock restart" };
    alarm 2;                   # schedule alarm in 10 seconds 
    eval { 
      while(<$fh>) {
        # discard the recorded data!
      }
    };
    alarm 0;                    # cancel the alarm
  };
  alarm 0;                        # race condition protection
  die if $@ && $@ !~ /alarm clock restart/; # reraise
  
  while(<$fh>) {
    if ($_ =~ /R([A-Fa-f0-9]{8})/) {$v = hex($1);}
    next if ($v>>16 & 0xffff) == 0xdead;

    #unless ($v & 0x80000000) {
    # print "-\n" unless $e;
    # $e = 1;
    # }
    #else { $e = 0;}

    next unless ($v & 0x80000000);
    next if $last == $v;
#     next unless $wordcount++ > 0;
    my $chan=($v>>26&0xf);
    my $edge=$v>>30 & 1;
    $counters[$chan][($v&0xf) + ($edge << 4)]++;    
    my $diff = ($v>>4 & 0x3fffff)*8+($v & 0x7) - ($last>>4 & 0x3fffff)*8-($last & 0x7);
    $diff += 2**25 if $diff < 0;
    printf("%i\t%i\t%03x\t%i\t%i\n",$edge, $v>>26 & 0xf, ($v & 0x0f), $v>>4 & 0x3fffff, $diff) if $verbose;
    $last = $v if ($edge==$invert_trigger) && ($chan == $timing_reference) ;
    }
  }


sub Cmd {
  my ($c) = @_;
  #print "send command '$c'\n";
  if ($c ne "") {
    my $s = $c . "T"x0 . "\n";
    #print "send string '$s'\n";
    print $fh $s;
    }
  #usleep(10);
  #sleep 1;
  #sleep 1;
  my $timeout = 1;
  #return;
  #print "try to read \n";
  my ($rec) = eval {
    local $SIG{ALRM} = sub { die "alarm\n" }; # NB: \n required
    alarm $timeout;
    #my $rec2 = <$fh>;
    my $rec2 ="";
    my $nread = sysread $fh, $rec2, 100;
    #print "received (n words: $nread) in eval: $rec2\n";
    alarm 0;
    $rec2;
  };
  if ($@) {
    die unless $@ eq "alarm\n";   # propagate unexpected errors
    print "timed out\n";
    # timed out
  }
  else {
   #print "received: $rec\n";
  }

#   return $rec;

  if ($rec =~ /R([A-Fa-f0-9]{8})/) {return hex($1);}

  return 0xdeadde99 if $poll;

  #print "%\n";
  #return 0xdeaddead;
  }

sub decode {
  my $v = shift @_;
  return 0 if($v == 0x001 || $v == 0x1fe);
  return 1 if($v == 0x003 || $v == 0x1fc);
  return 2 if($v == 0x007 || $v == 0x1f8);
  return 3 if($v == 0x00f || $v == 0x1f0);
  return 4 if($v == 0x01f || $v == 0x1e0);
  return 5 if($v == 0x03f || $v == 0x1c0);
  return 6 if($v == 0x07f || $v == 0x180);
  return 7 if($v == 0x0ff || $v == 0x100);
  return $v;
  }


$SIG{"INT"} =  \&finish;
$SIG{"QUIT"} =  \&stats;

sub finish{
    my $v = Cmd("W0000000000"); ## disable streaming
    stats();
    exit;
}
    
sub stats{
 for (my $j = 0 ; $j<9; $j++){
  print "----------------------\n";
  print "stats for channel $j:\n";
  print "Bin\tCnt1\tSize1\tCnt2\tSize2\n";
  my @sum;
  for(my $i=0; $i < 32; $i++){
    if ($counters[$j][$i]) {
      $sum[$i/16] += $counters[$j][$i];
      }
    }
  for(my $i=0; $i < 16; $i++){
    if ($counters[$j][$i]) {
      printf("%01x\t%i\t%i\t%i\t%i\n",$i,$counters[$j][$i],     $counters[$j][$i]/($sum[0]||1)*1000000/250,
                                         $counters[$j][$i+16], $counters[$j][$i+16]/($sum[1]||1)*1000000/250)
      }
    }
  print ("Sum:\t$sum[0]\t\t$sum[1]\n");
  my $cumulate_lead = 0;
  my @tarr_lead;
  for (my $i=0; $i < 8; $i++) {
#     print "$cumulate_lead, ";
    push(@tarr_lead,$cumulate_lead);
    $cumulate_lead+= $counters[$j][$i]/($sum[0]||1)*1000/250;
  }
  print "Double_t bin_calib_ch".$j."_fall[8] = {".join(", ",@tarr_lead)."};\n";
  my $cumulate_trail = 0;
  my @tarr_trail;
  for (my $i=16; $i < 24; $i++) {
#     print "$cumulate_trail, ";
    push(@tarr_trail,$cumulate_trail);
    $cumulate_trail+= $counters[$j][$i]/($sum[1]||1)*1000/250;
  }
  print "Double_t bin_calib_ch".$j."_rise[8] = {".join(", ",@tarr_trail)."};\n";
  print "----------------------\n";
  }
 }

# main



my $v; 

Cmd("W0000000001") unless $poll; #enable streaming

my $disable_mask_val = eval($disable_mask); # convert arbitrary input to number, either hex (0x) or binary (0b) or plain decimal 
Cmd("W11".sprintf("%08x",$disable_mask_val)); #  write disable register

print "Edge\tChan\tFine\tCoarse\tDiff to last leading edge in 500ps bins\n";  
if(!$poll) {Stream();}
else { # operating in ugly polling mode
  while(1) {
    $v = Cmd("$cmd");
    next if ($v>>16 & 0xffff) == 0xdead;
    unless ($v & 0x80000000) {next;}
    next if $last == $v;
    $counters[($v&0xf) + (($v>>30 & 1) << 8)]++;    
    my $diff = ($v>>4 & 0x3fffff)*8+($v & 0x7) - ($last>>4 & 0x3fffff)*8-($last & 0x7);
    $diff += 2**25 if $diff < 0;
    printf("%i\t%i\t%03x\t%i\t%i\n",$v>>30 & 1, $v>>26 & 0xf, ($v & 0x0f), $v>>4 & 0x3fffff, $diff) if $verbose;
    $last = $v if $v>>30 & 1;
    }
  }
  
  
stats();
