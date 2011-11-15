#!/usr/bin/perl

=head1 [street_parser.pl]

 description:

=cut

use File::Basename;
use Geo::StreetAddress::US;
use Text::CSV_XS;
use Tie::Handle::CSV;
#use Data::Dumper;
use JSON;
use strict;
use warnings;
use Getopt::Long;
use Cwd 'abs_path';

my $prog = $0;
my $usage = <<EOQ;
Usage for $0:

  >$prog [-test -help -verbose -address -file]

EOQ

my $date = get_date();

my $help;
my $test;
my $debug;
my $verbose = 1;
my $address = '';
my $file = '';

my $bsub;
my $log;
my $stdout;
my $stdin;
my $run;
my $dry_run;

my $ok = GetOptions(
                    'test'      => \$test,
                    'debug=i'   => \$debug,
                    'verbose=i' => \$verbose,
                    'help'      => \$help,
                    'log'       => \$log,
                    'address=s' => \$address,
                    'file=s'    => \$file,
                    
                    'run'       => \$run,
                    'dry_run'   => \$dry_run,
                   );

# output
my $json;
my $hashref;

if ($help || !$ok || !$file) {
  print $usage;
  exit;
}

sub trim {
  my $string = shift;
  $string =~ s/^\s+//;
	$string =~ s/\s+$//;
	return $string;
}

sub get_date {
  my ($day, $mon, $year) = (localtime)[3..5];
  return my $date= sprintf "%04d-%02d-%02d", $year+1900, $mon+1, $day;
}

sub output_localities {
  my $localities = shift;
  my $base_dir = shift;
  my @output_headers = qw(id name type);
  my $headers = join("|",@output_headers);
  
  # output file
  open my $wh, ">", "$base_dir/locality.txt" or die "$base_dir/locality.txt: $!";
  my $csv = Text::CSV_XS->new ({
    eol => $/,
    sep_char => "|"
  });
  
  print $wh "$headers" . "\n";
  
  foreach my $name (keys %{$localities}) {
    my @output_line;
    push(@output_line,($localities->{$name}, $name, "House District"));
    $csv->print($wh, \@output_line);
  }
  
  close $wh or die "$base_dir/locality.txt: $!";
  
  return;
}

sub output_precincts {
  my $precincts = shift;
  my $base_dir = shift;
  my @output_headers = qw(id name locality_id polling_location_id);
  my $headers = join("|",@output_headers);
  
  # output file
  open my $wh, ">", "$base_dir/precinct.txt" or die "$base_dir/precinct.txt: $!";
  my $csv = Text::CSV_XS->new ({
    eol => $/,
    sep_char => "|"
  });
  
  print $wh "$headers" . "\n";
  
  foreach my $id (keys %{$precincts}) {
    my @output_line;
    push(@output_line,($id, $precincts->{$id}->{name}, $precincts->{$id}->{locality_id}, $precincts->{$id}->{polling_location_id}));
    $csv->print($wh, \@output_line);
  }
  
  close $wh or die "$base_dir/precinct.txt: $!";
  
  return;
}

sub output_polling_locations {
  my $polling_locations = shift;
  my $base_dir = shift;
  my @output_headers = qw(id location_name line1 line2 city state zip);
  my $headers = join("|",@output_headers);
  
  # output file
  open my $wh, ">", "$base_dir/polling_location.txt" or die "$base_dir/polling_location.txt: $!";
  my $csv = Text::CSV_XS->new ({
    eol => $/,
    sep_char => "|"
  });
  
  print $wh "$headers" . "\n";
  
  foreach my $id (keys %{$polling_locations}) {
    my @output_line;
    push(@output_line,($id, $polling_locations->{$id}->{location_name}, $polling_locations->{$id}->{line1}, $polling_locations->{$id}->{line2}, $polling_locations->{$id}->{city}, $polling_locations->{$id}->{state}, $polling_locations->{$id}->{zip}));
    $csv->print($wh, \@output_line);
  }
  
  close $wh or die "$base_dir/polling_location.txt: $!";
  
  return;
}

sub parse_csv_args {
  my $csv_str = shift;
  return [split ',', $csv_str];
}

if ($file) {
  # get file minutia
  my $path =  abs_path($file) or die "File Not Found: $!";
  my $base_dir = dirname($path) or die "Directory Not Found: $!";
  my $header;
  my @output_headers = qw(id start_house_number end_house_number odd_even_both street_direction street_name street_suffix address_direction state city zip precinct_id);
  my $street_headers = join("|", @output_headers);
  my $localities = {};
  my $precincts = {};
  my $cities = {}; # keep track of cities/towns that vote in one location
  my $polling_locations = {};
  
  # set up the CSV reader
  my $fh = Tie::Handle::CSV->new(
    $file,
    header => 1,
    key_case => 'lower',
    sep_char => ','
  );  
  
  # output file                                                                                                                                                                                                 
  open my $wh, ">", "$base_dir/street_segment.txt" or die "$base_dir/street_segment.txt: $!";
  my $csv = Text::CSV_XS->new ({
    eol => $/,
    sep_char => "|"
  });
  
  $header = $fh->header;
  
  
  # read from file
  while (my $csv_line = <$fh>) {
    my @output_line;
    
#     foreach my $key (keys %{$csv_line}) {
#       print $csv_line . "\n";
#       $csv_line->{$key} = trim($csv_line->{$key})
#     }
    
    # because the reader eats the header, line number starts at '2'                                                                                                                                             
    if ($. == 2) {
      print $wh "$street_headers" . "\n";
    }
    
    if(!exists $localities->{$csv_line->{'house_district'}}) {
      $localities->{$csv_line->{'house_district'}} = $csv_line->{'house_district'};
      # ASSERT: Counties are in ascending order
      # ...which doesn't help in this case
    }
    
    if(!exists $precincts->{$localities->{$csv_line->{'house_district'}} . $csv_line->{'precinct_id'}}) {
      $precincts->{$localities->{$csv_line->{'house_district'}} . $csv_line->{'precinct_id'}} = {
        name => "House District " . $csv_line->{'house_district'} . " Precinct " . $csv_line->{'precinct_id'},
        locality_id => $localities->{$csv_line->{'house_district'}},
        polling_location_id => $localities->{$csv_line->{'house_district'}} . $csv_line->{'precinct_id'} . "1",
      };
    }
    
    if($csv_line->{'unassigned1'} =~ /\*/) {
      if(!exists $cities->{$csv_line->{'house_district'} . $csv_line->{'precinct_id'}}) {
        $cities->{$csv_line->{'house_district'} . $csv_line->{'precinct_id'}} = {
          id => $csv_line->{'id'},
          start_house_number => $csv_line->{'low_mileage_number_fraction'} || "0",
          end_house_number => $csv_line->{'high_milage_number_fraction'} || "0",
          odd_even_both => "both",
          street_direction => $csv_line->{'street_direction'},
          street_name => "*",
          street_suffix => $csv_line->{'street_type'},
          address_direction => $csv_line->{'address_direction'},
          state => "AK",
          city => $csv_line->{'city'},
          zip => $csv_line->{'zip'},
          precinct_id => $csv_line->{'house_district'} . $csv_line->{'precinct_id'},
        };
      }
      
      next;
    }
    
    push(@output_line, (
      $csv_line->{'id'},
      $csv_line->{'start_house_number'} || 1,
      $csv_line->{'end_house_number'} || 999999,
      $csv_line->{'odd_even_both'} || "both",
      $csv_line->{'street_direction'},
      $csv_line->{'street_name'},
      $csv_line->{'street_type'},
      $csv_line->{'address_direction'},
      $csv_line->{'state'},
      $csv_line->{'city'},
      $csv_line->{'zip'},
      $csv_line->{'house_district'} . $csv_line->{'precinct_id'},
    ));
    
    $csv->print($wh, \@output_line);
  }
  
#   foreach my $key (keys %{$cities}) {
#     my @output_line;
#     push(@output_line, (
#       $cities->{$key}->{'id'},
#       $cities->{$key}->{'start_house_number'},
#       $cities->{$key}->{'end_house_number'},
#       $cities->{$key}->{'odd_even_both'},
#       $cities->{$key}->{'street_direction'},
#       $cities->{$key}->{'street_name'},
#       $cities->{$key}->{'street_suffix'},
#       $cities->{$key}->{'address_direction'},
#       $cities->{$key}->{'state'},
#       $cities->{$key}->{'city'},
#       $cities->{$key}->{'zip'},
#       $cities->{$key}->{'precinct_id'},
#     ));
# 
#     $csv->print($wh, \@output_line);
#   }
  
  close $wh or die "localities.txt: $!";
  
  output_localities($localities, $base_dir);
  output_precincts($precincts, $base_dir);
}

my $run_time = time() - $^T;

print "Job took $run_time seconds\n";

#if ($address) {
#    $hashref = Geo::StreetAddress::US->parse_address($address);
#    $hashref = Geo::StreetAddress::US->parse_location($address) || { error => 'Could not geocode' };
#    $json = encode_json $hashref;
#    print "$json";
#}