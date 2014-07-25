package Device::Neurio;

use warnings;
use strict;
use 5.006_001; 

require Exporter;

our @ISA = qw(Exporter);

# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.

# This allows declaration	use Device::NeurioTools ':all';
# If you do not need this, moving things directly into @EXPORT or @EXPORT_OK
# will save memory.

our %EXPORT_TAGS = ( 'all' => [ qw(
    new connect fetch_Recent_Live fetch_Last_Live fetch_Samples fetch_Full_Samples fetch_Energy_Stats
) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );
our @EXPORT = qw( $EXPORT_TAGS{'all'});

BEGIN
{
  if ($^O eq "MSWin32"){
    use LWP::UserAgent;
    use JSON qw(decode_json encode_json);
    use MIME::Base64 (qw(encode_base64));
    use Data::Dumper;
  } else {
    use LWP::UserAgent;
    use JSON qw(decode_json encode_json);
    use MIME::Base64 (qw(encode_base64));
    use Data::Dumper;
  }
}


=head1 NAME

Device::Neurio - Methods for wrapping the Neurio API calls so that they are 
                 accessible via Perl

=head1 VERSION

Version 0.12

=cut

our $VERSION = '0.12';

#*****************************************************************

=head1 SYNOPSIS

 This module provides a Perl interface to a Neurio sensor via the following 
 methods:
   - new
   - connect
   - fetch_Last_Live
   - fetch_Recent_Live
   - fetch_Samples
   - fetch_Full_samples
   - fetch_Energy_Stats

 Please note that in order to use this module you will require three parameters
 (key, secret, sensor_id) as well as an Energy Aware Neurio sensor installed in
 your house.

 The module is written entirely in Perl and has been developped on Raspbian Linux.

 All date/time values are specified using ISO8601 format (yyyy-mm-ddThh:mm:ssZ)

=head1 SAMPLE CODE

    use Device::Neurio;

    $my_Neurio = Device::Neurio->new($key,$secret,$sensor_id,$debug);

    $my_Neurio->connect();
  
    $data = $my_Neurio->fetch_Last_Live();
    print $data->{'consumptionPower'}

    $data = $my_Neurio->fetch_Recent_Live("2014-06-18T19:20:21Z");
    print $data->[0]->{'consumptionPower'}

    undef $my_Neurio;


=head2 EXPORT

 All by default.


=head1 SUBROUTINES/METHODS

=head2 new - the constructor for a Neurio object

 Creates a new instance which will be able to fetch data from a unique Neurio 
 sensor.

 my $Neurio = Device::Neurio->new($key, $secret, $sensor_id, $debug);

   This method accepts the following parameters:
     - $key       : unique key for the account - Required 
     - $secret    : secret key for the account - Required 
     - $sensor_id : sensor ID connected to the account - Required 
     - $debug     : enable or disable debug messages (disabled by default - Optional)

 Returns a Neurio object if successful.
 Returns 0 on failure
 
=cut

sub new {
    my $class = shift;
    my $self;
    
    $self->{'ua'}        = LWP::UserAgent->new();
    $self->{'key'}       = shift;
    $self->{'secret'}    = shift;
    $self->{'sensor_id'} = shift;
    $self->{'debug'}     = shift;
    $self->{'base64'}    = encode_base64($self->{'key'}.":".$self->{'secret'});
    chomp($self->{'base64'});
    
    if (!defined $self->{'debug'}) {
      $self->{'debug'} = 0;
    }
    
    if ((!defined $self->{'key'}) || (!defined $self->{'secret'}) || (!defined $self->{'sensor_id'})) {
      print "\nNeurio->new(): Key, Secret and Sensor_ID are REQUIRED parameters.\n";
      return 0;
    }
    
    $self->{'base_url'}         = "https://api-staging.neur.io/v1/samples";
    $self->{'Recent_Live_url'}  = $self->{'base_url'}."/live?sensorId=".$self->{'sensor_id'};
    $self->{'Last_Live_url'}    = $self->{'base_url'}."/live/last?sensorId=".$self->{'sensor_id'};
    $self->{'Samples_url'}      = $self->{'base_url'}."?sensorId=".$self->{'sensor_id'};
    $self->{'Full_Samples_url'} = $self->{'base_url'}."/full?sensorId=".$self->{'sensor_id'};
    $self->{'Energy_Stats_url'} = $self->{'base_url'}."/stats?sensorId=".$self->{'sensor_id'};
    $self->{'last_code'}        = '';
    $self->{'last_reason'}      = '';
    
    bless $self, $class;
    
    return $self;
}


#*****************************************************************

=head2 connect - open a secure connection to the Neurio server

 Opens a secure connection via HTTPS to the Neurio server which provides
 access to a set of API commands to access the sensor data.

   $Neurio->connect();
 
 This method accepts no parameters
 
 Returns 1 on success 
 Returns 0 on failure
 
=cut

sub connect {
	my $self         = shift;
	my $access_token = '';
	
    # Submit request for authentiaction token.
    my $response = $self->{'ua'}->post('https://api-staging.neur.io/v1/oauth2/token',
          { basic_authentication => $self->{'base64'},
        	Content_Type         => 'application/x-www-form-urlencoded',
        	grant_type           => 'client_credentials', 
        	client_id            => $self->{'key'},
        	client_secret        => $self->{'secret'},
          }
        );
    
    if($response->is_success) {
      my $return = $response->content;
      $return =~ /\"access_token\":\"(.*)\"\,\"token_type\"/;
      $self->{'access_token'} = $1;
      return 1;
    } else {
      print "\nDevice::Neurio->connect(): Failed to connect.\n";
      print $response->content."\n\n";
      return 0;
    }
}


#*****************************************************************

=head2 fetch_Recent_Live - Fetch recent sensor samples

 Retrieves recent sensor readings from the Neurio server.
 The values represent the sum of all phases.

   $Neurio->fetch_Recent_Live($last);
 
   This method accepts the following parameters:
      $last - time of last sample received (yyyy-mm-ddThh:mm:ssZ) - Optional
              specified using ISO8601 format
      
      If no value is specified for $last, a default of 2 minutes is used.
 
 Returns an array of Perl data structures on success
 $VAR1 = [
          {
            'generationEnergy' => 3716166644,
            'timestamp' => '2014-06-24T11:08:00.000Z',
            'consumptionEnergy' => 6762651207,
            'generationPower' => 564,
            'consumptionPower' => 821
          },
          ...
         ]
 Returns 0 on failure
 
=cut

sub fetch_Recent_Live {
    my ($self,$last) = @_;
    my ($url,$response,$decoded_response);

    # if optional parameter is defined, add it
    if (defined $last) {
      $url = $self->{'Recent_Live_url'}."&last=$last";
    } else {
      $url = $self->{'Recent_Live_url'};
    }
    return $self->__process_get($url);
}


#*****************************************************************

=head2 fetch_Last_Live - Fetch the last live sensor sample

 Retrieves the last live sensor reading from the Neurio server.  
 The values represent the sum of all phases.

   $Neurio->fetch_Last_Live();

   This method accepts no parameters
 
 Returns a Perl data structure on success:
 $VAR1 = {
          'generationEnergy' => 3716027450,
          'timestamp' => '2014-06-24T11:03:43.000Z',
          'consumptionEnergy' => 6762445671,
          'generationPower' => 542,
          'consumptionPower' => 800
        };
 Returns 0 on failure
 
=cut

sub fetch_Last_Live {
    my $self = shift;
    my ($url,$response,$decoded_response);
    
    $url = $self->{'Last_Live_url'};
    
    return $self->__process_get($url);
}


#*****************************************************************

=head2 fetch_Samples - Fetch sensor samples from the Neurio server

 Retrieves sensor readings within the parameters specified.
 The values represent the sum of all phases.

 $Neurio->fetch_Samples($start,$granularity,$end,$frequency,$perPage,$page);

   This method accepts the following parameters:
     - start       : yyyy-mm-ddThh:mm:ssZ - Required
                     specified using ISO8601 format
     - granularity : seconds|minutes|hours|days - Required
     - end         : yyyy-mm-ddThh:mm:ssZ - Optional
                     specified using ISO8601 format
     - frequency   : if the granularity is specified as 'minutes', then the 
                     frequency must be a multiple of 5 - Optional
     - perPage     : number of results per page - Optional
     - page        : page number to return - Optional
 
 Returns an array of Perl data structures on success
     $VAR1 = [
              {
                'generationEnergy' => 3568948578,
                'timestamp' => '2014-06-21T19:00:00.000Z',
                'consumptionEnergy' => 6487889194,
                'generationPower' => 98,
                'consumptionPower' => 240
              },
             ...
             ]
 Returns 0 on failure
 
=cut

sub fetch_Samples {
    my ($self,$start,$granularity,$end,$frequency,$perPage,$page) = @_;
    my ($url,$response,$decoded_response);
    
    # make sure $start and $granularity are defined
    if ((!defined $start) || (!defined $granularity)) {
      print "\nNeurio->fetch_Full_Samples(): \$start and \$granularity are required parameters\n\n";
      return 0;
    }
    # make sure that frequqncy is a multiple of 5 if $granularity is in minutes
    if (($granularity eq 'minutes') and defined $frequency) {
      if (eval($frequency%5) != 0) {
        print "\nNeurio->fetch_Samples(): Only multiples of 5 are supported for \$frequency when \$granularity is in minutes\n\n";
        return 0;
      }
    }
    # make sure $granularity is one of the correct values
    if (!($granularity =~ /[seconds|minutes|hours|days]/)) {
      print "\nNeurio->fetch_Full_Samples(): Only values of 'seconds, minutes, hours or days' are supported for \$granularity\n\n";
      return 0;
    }
    
    $url = $self->{'Samples_url'}."&start=$start&granularity=$granularity";
    
    # if optional parameter is defined, add it
    if (defined $end) {
      $url = $url . "&end=$end";
    }
    # if optional parameter is defined, add it
    if (defined $frequency) {
      $url = $url . "&frequency=$frequency";
    }
    # if optional parameter is defined, add it
    if (defined $perPage) {
      $url = $url . "&perPage=$perPage";
    }
    # if optional parameter is defined, add it
    if (defined $page) {
      $url = $url . "&page=$page";
    }
    
    return $self->__process_get($url);
}


#*****************************************************************

=head2 fetch_Full_Samples - Fetches full samples for all phases

 Retrieves full sensor readings including data for each individual phase within 
 the parameters specified.

 $Neurio->fetch_Full_Samples($start,$granularity,$end,$frequency,$perPage,$page);

   This method accepts the following parameters:
     - start       : yyyy-mm-ddThh:mm:ssZ - Required
                     specified using ISO8601 format
     - granularity : seconds|minutes|hours|days - Required
     - end         : yyyy-mm-ddThh:mm:ssZ - Optional
                     specified using ISO8601 format
     - frequency   : an integer - Optional
     - perPage     : number of results per page - Optional
     - page        : page number to return - Optional
 
 Returns an array of Perl data structures on success
 $VAR1 = [
          {
            'timestamp' => '2014-06-16T19:20:21.000Z',
            'channelSamples' => [
                                  {
                                    'voltage' => '123.19',
                                    'power' => 129,
                                    'name' => '1',
                                    'energyExported' => 27,
                                    'channelType' => 'phase_a',
                                    'energyImported' => 2682910899,
                                    'reactivePower' => 41
                                  },
                                  {
                                    'voltage' => '123.94',
                                    'power' => 199,
                                    'name' => '2',
                                    'energyExported' => 6,
                                    'channelType' => 'phase_b',
                                    'energyImported' => 3296564362,
                                    'reactivePower' => -45
                                  },
                                  {
                                    'voltage' => '123.57',
                                    'power' => 327,
                                    'name' => '3',
                                    'energyExported' => 10,
                                    'channelType' => 'consumption',
                                    'energyImported' => 5979475235,
                                    'reactivePower' => -4
                                  }
                                ]
          },
          ...
         ]
 Returns 0 on failure
 
=cut

sub fetch_Full_Samples {
    my ($self,$start,$granularity,$end,$frequency,$perPage,$page) = @_;
    my ($url,$response,$decoded_response);
    
    # make sure $start and $granularity are defined
    if ((!defined $start) || (!defined $granularity)) {
      print "\nNeurio->fetch_Full_Samples(): \$start and \$granularity are required parameters\n\n";
      return 0;
    }
    # make sure $granularity is one of the correct values
    if (!($granularity =~ /[seconds|minutes|hours|days]/)) {
      print "\nNeurio->fetch_Full_Samples(): Found \$granularity of $granularity\nOnly values of 'seconds, minutes, hours or days' are supported for \$granularity\n\n";
      return 0;
    }
    
    $url = $self->{'Full_Samples_url'}."&start=$start&granularity=$granularity";
    
    # if optional parameter is defined, add it
    if (defined $end) {
      $url = $url . "&end=$end";
    }
    # if optional parameter is defined, add it
    if (defined $frequency) {
      $url = $url . "&frequency=$frequency";
    }
    # if optional parameter is defined, add it
    if (defined $perPage) {
      $url = $url . "&perPage=$perPage";
    }
    # if optional parameter is defined, add it
    if (defined $page) {
      $url = $url . "&page=$page";
    }
    
    return $self->__process_get($url);
}


#*****************************************************************

=head2 fetch_Energy_Stats - Fetches energy statistics

 Retrieves energy statistics within the parameters specified.
 The values represent the sum of all phases.

   $Neurio->fetch_Energy_Stats($start,$granularity,$end,$frequency,$perPage,$page);

   This method accepts the following parameters:
     - start       : yyyy-mm-ddThh:mm:ssZ - Required
                     specified using ISO8601 format
     - granularity : minutes|hours|days|months - Required
     - end         : yyyy-mm-ddThh:mm:ssZ - Optional
                     specified using ISO8601 format
     - frequency   : if the granularity is specified as 'minutes', then the 
                     frequency must be a multiple of 5 - Optional
     - perPage     : number of results per page - Optional
     - page        : page number to return - Optional
 
 Returns a Perl data structure containing all the raw data
 Returns 0 on failure
 
=cut

sub fetch_Energy_Stats {
    my ($self,$start,$granularity,$end,$frequency,$perPage,$page) = @_;
    my ($url,$response,$decoded_response);

    # make sure $start and $granularity are defined
    if ((!defined $start) || (!defined $granularity)) {
      print "\nNeurio->fetch_Energy_Stats(): \$start and \$granularity are required parameters\n\n";
      return 0;
    }
    # make sure that frequqncy is a multiple of 5 if $granularity is in minutes
    if (($granularity eq 'minutes') and defined $frequency) {
      if (eval($frequency%5) != 0) {
        print "\nNeurio->fetch_Energy_Stats(): Only multiples of 5 are supported for \$frequency when \$granularity is in minutes\n\n";
        return 0;
      }
    }
    # make sure $granularity is one of the correct values
    if (!($granularity ~~ ['minutes','hours','days','months'])) {
      print "\nNeurio->fetch_Full_Samples(): Only values of 'minutes, hours, days or months' are supported for \$granularity\n\n";
      return 0;
    }
    
    $url = $self->{'Energy_Stats_url'}."&start=$start&granularity=$granularity";
    
    # if optional parameter is defined, add it
    if (defined $end) {
      $url = $url . "&end=$end";
    }
    # if optional parameter is defined, add it
    if (defined $frequency) {
      $url = $url . "&frequency=$frequency";
    }
    # if optional parameter is defined, add it
    if (defined $perPage) {
      $url = $url . "&perPage=$perPage";
    }
    # if optional parameter is defined, add it
    if (defined $page) {
      $url = $url . "&page=$page";
    }
    
    return $self->__process_get($url);
}

#*****************************************************************

=head2 dump_Object - shows the contents of the local Neurio object

 shows the contents of the local Neurio object in human readable form

   $Neurio->dump_Object();

   This method accepts no parameters
 
 Returns nothing
 
=cut

sub dump_Object {
    my $self  = shift;
    
    print "Key             : ".substr($self->{'key'},              0,120)."\n";
    print "SecretKey       : ".substr($self->{'secret'},           0,120)."\n";
    print "Sensor_ID       : ".substr($self->{'sensor_id'},        0,120)."\n";
    print "Access_token    : ".substr($self->{'access_token'},     0,120)."\n";
    print "Base 64         : ".substr($self->{'base64'},           0,120)."\n";
    print "Base URL        : ".substr($self->{'base_url'},         0,120)."\n";
    print "Recent Live URL : ".substr($self->{'Recent_Live_url'},  0,120)."\n";
    print "Last Live URL   : ".substr($self->{'Last_Live_url'},    0,120)."\n";
    print "Samples URL     : ".substr($self->{'Samples_url'},      0,120)."\n";
    print "Full Samples URL: ".substr($self->{'Full_Samples_url'}, 0,120)."\n";
    print "Energy Stats URL: ".substr($self->{'Energy_Stats_url'}, 0,120)."\n";
    print "debug           : ".substr($self->{'debug'}           , 0,120)."\n";
    print "last_code       : ".substr($self->{'last_code'}       , 0,120)."\n";
    print "last_reason     : ".substr($self->{'last_reason'}     , 0,120)."\n";
    
    print "\n";
}


#*****************************************************************

=head2 get_last_reason - returns the text generated by the most recent fetch

 Returns the HTTP Header reason for the most recent fetch command

   $Neurio->get_last_reason();

   This method accepts no parameters
 
 Returns the textual reason
 
=cut

sub get_last_reason {
    my $self  = shift;
    return $self->{'last_reason'};
}

#*****************************************************************

=head2 get_last_code - returns the code generated by the most recent fetch

 Returns the HTTP Header code for the most recent fetch command

   $Neurio->get_last_code();

   This method accepts no parameters
 
 Returns the numeric code
 
=cut

sub get_last_code {
    my $self  = shift;
    return $self->{'last_code'};
}

#*****************************************************************

sub __process_get {
    my $self     = shift;
    my $url      = shift;
	my $response = $self->{'ua'}->get($url,"Authorization"=>"Bearer ".$self->{'access_token'});
	
    $self->{'last_reason'} = decode_json($response->content)->{'code'};
    $self->{'last_code'}   = $response->code;
    
    if ($response->is_success) {
      return decode_json($response->content);
    } else {
      print "\n".(caller(1))[3]."(): Failed with return code ".$self->get_last_code()." - ".$self->get_last_reason()."\n";
      return 0;
    }
}

#*****************************************************************

=head1 AUTHOR

Kedar Warriner, C<kedar at cpan.org>

=head1 BUGS

 Please report any bugs or feature requests to C<bug-device-Neurio at rt.cpan.org>
 or through the web interface at http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Device-Neurio
 I will be notified, and then you'll automatically be notified of progress on 
 your bug as I make changes.

=head1 SUPPORT

 You can find documentation for this module with the perldoc command.

  perldoc Device::Neurio

 You can also look for information at:

=over 5

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Device-Neurio>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Device-Neurio>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Device-Neurio>

=item * Search CPAN

L<http://search.cpan.org/dist/Device-Neurio/>

=back

=head1 ACKNOWLEDGEMENTS

 Many thanks to:
  The guys at Energy Aware Technologies for creating the Neurio sensor and 
      developping the API.
  Everyone involved with CPAN.

=head1 LICENSE AND COPYRIGHT

 Copyright 2014 Kedar Warriner <kedar at cpan.org>.

 This program is free software; you can redistribute it and/or modify it
 under the terms of either: the GNU General Public License as published
 by the Free Software Foundation; or the Artistic License.

 See http://dev.perl.org/licenses/ for more information.

=cut

#********************************************************************
1; # End of Device::Neurio - Return success to require/use statement
#********************************************************************


