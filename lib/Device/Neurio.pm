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
    new connect fetch_Samples_Recent_Live fetch_Samples_Last_Live fetch_Samples 
    fetch_Samples_Full fetch_Stats_Energy
) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );
our @EXPORT = qw( $EXPORT_TAGS{'all'});

BEGIN
{
  if ($^O eq "MSWin32"){
    use LWP::UserAgent;
    use Time::Local;
    use JSON qw(decode_json encode_json);
    use MIME::Base64 (qw(encode_base64));
    use Data::Dumper;
  } else {
    use LWP::UserAgent;
    use Time::Local;
    use JSON qw(decode_json encode_json);
    use MIME::Base64 (qw(encode_base64));
    use Data::Dumper;
  }
}


=head1 NAME

Device::Neurio - Methods for wrapping the Neurio API calls so that they are 
                 accessible via Perl

=head1 VERSION

Version 0.14

=cut

our $VERSION = '0.14';

#******************************************************************************
=head1 SYNOPSIS

 This module provides a Perl interface to a Neurio sensor via the following 
 methods:
   - new
   - connect
   - fetch_Samples
   - fetch_Samples_Full
   - fetch_Samples_Last_Live
   - fetch_Samples_Recent_Live
   - fetch_Stats_Energy
   - fetch_Appliances
   - fetch_Appliances_Events
   - fetch_Appliances_Specific
   - fetch_Appliances_Stats

 Please note that in order to use the 'Samples' methods in this module you will 
 require three parameters (key, secret, sensor_id) as well as an Energy Aware 
 Neurio sensor installed in your house.  In order to use the 'Appliances'
 methods, you will also require another parameter (location_id).  This information
 can be obtained from the Neurio developpers website.

 The module is written entirely in Perl and was developped on Raspbian Linux.

 All date/time values are specified using ISO8601 format (yyyy-mm-ddThh:mm:ssZ)

=head1 SAMPLE CODE

    use Device::Neurio;

    $my_Neurio = Device::Neurio->new($key,$secret,$sensor_id,$debug);

    $my_Neurio->connect();
  
    $data = $my_Neurio->fetch_Samples_Last_Live();
    print $data->{'consumptionPower'}

    $data = $my_Neurio->fetch_Samples_Recent_Live("2014-06-18T19:20:21Z");
    print $data->[0]->{'consumptionPower'}

    undef $my_Neurio;


=head2 EXPORT

 All by default.


=head1 SUBROUTINES/METHODS

=head2 new - the constructor for a Neurio object

 Creates a new instance which will be able to fetch data from a unique Neurio 
 sensor.  All three parameters are required and can be obtained from the
 Neurio developpers website.

 my $Neurio = Device::Neurio->new($key, $secret, $sensor_id, $debug);

   This method accepts the following parameters:
     - $key       : unique key for the account - Required 
     - $secret    : secret key for the account - Required 
     - $sensor_id : sensor ID connected to the account - Required 
     - $debug     : turn on debug messages - Optional

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
      print "\nNeurio->new(): Key, Secret and Sensor_ID are REQUIRED parameters\n" if ($self->{'debug'});
      $self->{'last_code'}      = '0';
      $self->{'last_reason'}    = 'Neurio->new(): Key, Secret and Sensor_ID are REQUIRED parameters';
      return 0;
    }
    
#    $self->{'base_url'}                = "https://api-staging.neur.io/v1";
    $self->{'base_url'}                = "https://api.neur.io/v1";
    $self->{'Samples_Recent_Live_url'} = $self->{'base_url'}."/samples/live?sensorId=".$self->{'sensor_id'};
    $self->{'Samples_Last_Live_url'}   = $self->{'base_url'}."/samples/live/last?sensorId=".$self->{'sensor_id'};
    $self->{'Samples_url'}             = $self->{'base_url'}."/samples?sensorId=".$self->{'sensor_id'};
    $self->{'Samples_Full_url'}        = $self->{'base_url'}."/samples/full?sensorId=".$self->{'sensor_id'};
    $self->{'Stats_Energy_url'}        = $self->{'base_url'}."/samples/stats?sensorId=".$self->{'sensor_id'};
    $self->{'Appliances_url'}          = $self->{'base_url'}."/appliances";
    $self->{'Appliances_Specific_url'} = $self->{'base_url'}."/appliances/";
    $self->{'Appliances_Stats_url'}    = $self->{'base_url'}."/appliances/stats";
    $self->{'Appliances_Events_url'}   = $self->{'base_url'}."/appliances/events";
    $self->{'last_code'}               = '';
    $self->{'last_reason'}             = '';
    
    bless $self, $class;
    
    return $self;
}


#******************************************************************************
=head2 connect - open a secure connection to the Neurio server

 Opens a secure connection via HTTPS to the Neurio server which provides
 access to a set of API commands to access the sensor data.
 
 An optional location ID can be given.  This is only required if calls
 will be made to the 'Appliance' methods.  Calls to the 'Samples'
 methods do not require that a location ID be set.  If a location_id is not
 specified at connection, then it must be specified when using the 'Appliance'
 methods.
 
 A location ID can be acquired from the Neurio developpers web site

   $Neurio->connect($location_id);
 
   This method accepts the following parameter:
     - $location_id : unique location id - Optional 
 
 Returns 1 on success 
 Returns 0 on failure
 
=cut

sub connect {
    my ($self,$location_id) = @_;
	my $access_token        = '';
	
    if (defined $location_id) {
      $self->{'location_id'} = $location_id;
    } else {
      $self->{'location_id'} = '';
    }

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
      print "\nDevice::Neurio->connect(): Failed to connect.\n" if ($self->{'debug'});
      print $response->content."\n\n" if ($self->{'debug'});
      $self->{'last_code'}   = '0';
      $self->{'last_reason'} = 'Neurio->new(): Device::Neurio->connect(): Failed to connect';
      return 0;
    }
}


#******************************************************************************
=head2 fetch_Samples_Recent_Live - Fetch recent sensor samples

 Retrieves recent sensor readings from the Neurio server.
 The values represent the sum of all phases.

   $Neurio->fetch_Samples_Recent_Live($last);
 
   This method accepts the following parameters:
      $last - time of last sample received specified using ISO8601 
              format (yyyy-mm-ddThh:mm:ssZ)  - Optional
      
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

sub fetch_Samples_Recent_Live {
    my ($self,$last) = @_;
    my $url;

    # if optional parameter is defined, add it
    if (defined $last) {
      $url = $self->{'Samples_Recent_Live_url'}."&last=$last";
    } else {
      $url = $self->{'Samples_Recent_Live_url'};
    }
    return $self->__process_get($url);
}


#******************************************************************************
=head2 fetch_Samples_Last_Live - Fetch the last live sensor sample

 Retrieves the last live sensor reading from the Neurio server.
 The values represent the sum of all phases.

   $Neurio->fetch_Samples_Last_Live();

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

sub fetch_Samples_Last_Live {
    my $self = shift;
    my $url = $self->{'Samples_Last_Live_url'};
    return $self->__process_get($url);
}


#******************************************************************************
=head2 fetch_Samples - Fetch sensor samples from the Neurio server

 Retrieves sensor readings within the parameters specified.
 The values represent the sum of all phases.

 $Neurio->fetch_Samples($start,$granularity,$end,$frequency,$perPage,$page);

   This method accepts the following parameters:
     - $start       : yyyy-mm-ddThh:mm:ssZ - Required
                      specified using ISO8601 format
     - $granularity : seconds|minutes|hours|days - Required
     - $end         : yyyy-mm-ddThh:mm:ssZ - Optional
                      specified using ISO8601 format
     - $frequency   : if the granularity is specified as 'minutes', then the 
                      frequency must be a multiple of 5 - Optional
     - $perPage     : number of results per page - Optional
     - $page        : page number to return - Optional
 
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
    
    # make sure $start and $granularity are defined
    if ((!defined $start) || (!defined $granularity)) {
      print "\nNeurio->fetch_Samples_Full(): \$start and \$granularity are required parameters\n\n" if ($self->{'debug'});
      $self->{'last_code'}   = '0';
      $self->{'last_reason'} = 'Neurio->fetch_Samples_Full(): \$start and \$granularity are required parameters';
      return 0;
    }
    # make sure that frequqncy is a multiple of 5 if $granularity is in minutes
    if (($granularity eq 'minutes') and defined $frequency) {
      if (eval($frequency%5) != 0) {
        print "\nNeurio->fetch_Samples(): Only multiples of 5 are supported for \$frequency when \$granularity is in minutes\n\n" if ($self->{'debug'});
      $self->{'last_code'}   = '0';
      $self->{'last_reason'} = 'Neurio->fetch_Samples(): Only multiples of 5 are supported for \$frequency when \$granularity is in minutes';
        return 0;
      }
    }
    # make sure $granularity is one of the correct values
    if (!($granularity =~ /[seconds|minutes|hours|days]/)) {
      print "\nNeurio->fetch_Samples_Full(): Only values of 'seconds, minutes, hours or days' are supported for \$granularity\n\n" if ($self->{'debug'});
      $self->{'last_code'}   = '0';
      $self->{'last_reason'} = 'Neurio->fetch_Samples_Full(): Only values of "seconds, minutes, hours or days" are supported for \$granularity';
      return 0;
    }
    
    my $url = $self->{'Samples_url'}."&start=$start&granularity=$granularity";
    
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


#******************************************************************************
=head2 fetch_Samples_Full - Fetches full samples for all phases

 Retrieves full sensor readings including data for each individual phase within 
 the parameters specified.

 $Neurio->fetch_Samples_Full($start,$granularity,$end,$frequency,$perPage,$page);

   This method accepts the following parameters:
     - $start       : yyyy-mm-ddThh:mm:ssZ - Required
                      specified using ISO8601 format
     - $granularity : seconds|minutes|hours|days - Required
     - $end         : yyyy-mm-ddThh:mm:ssZ - Optional
                      specified using ISO8601 format
     - $frequency   : an integer - Optional
     - $perPage     : number of results per page - Optional
     - $page        : page number to return - Optional
 
 Returns an array of Perl data structures on success
 [
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

sub fetch_Samples_Full {
    my ($self,$start,$granularity,$end,$frequency,$perPage,$page) = @_;
    
    # make sure $start and $granularity are defined
    if ((!defined $start) || (!defined $granularity)) {
      print "\nNeurio->fetch_Samples_Full(): \$start and \$granularity are required parameters\n\n" if ($self->{'debug'});
      $self->{'last_code'}   = '0';
      $self->{'last_reason'} = 'Neurio->fetch_Samples_Full(): \$start and \$granularity are required parameters';
      return 0;
    }
    # make sure $granularity is one of the correct values
    if (!($granularity =~ /[seconds|minutes|hours|days]/)) {
      print "\nNeurio->fetch_Samples_Full(): Found \$granularity of $granularity\nOnly values of 'seconds, minutes, hours or days' are supported for \$granularity\n\n" if ($self->{'debug'});
      $self->{'last_code'}   = '0';
      $self->{'last_reason'} = 'Neurio->fetch_Samples_Full(): Only values of "seconds, minutes, hours or days" are supported for \$granularity';
      return 0;
    }
    
    my $url = $self->{'Samples_Full_url'}."&start=$start&granularity=$granularity";
    
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


#******************************************************************************
=head2 fetch_Stats_Energy - Fetches energy statistics

 Retrieves energy statistics within the parameters specified.
 The values represent the sum of all phases.

   $Neurio->fetch_Stats_Energy($start,$granularity,$end,$frequency,$perPage,$page);

   This method accepts the following parameters:
     - $start       : yyyy-mm-ddThh:mm:ssZ - Required
                      specified using ISO8601 format
     - $granularity : minutes|hours|days|months - Required
     - $end         : yyyy-mm-ddThh:mm:ssZ - Optional
                      specified using ISO8601 format
     - $frequency   : if the granularity is specified as 'minutes', then the 
                      frequency must be a multiple of 5 - Optional
     - $perPage     : number of results per page - Optional
     - $page        : page number to return - Optional
 
 Returns a Perl data structure containing all the raw data
 Returns 0 on failure
 
=cut

sub fetch_Stats_Energy {
    my ($self,$start,$granularity,$end,$frequency,$perPage,$page) = @_;

    # make sure $start and $granularity are defined
    if ((!defined $start) || (!defined $granularity)) {
      print "\nNeurio->fetch_Stats_Energy(): \$start and \$granularity are required parameters\n\n" if ($self->{'debug'});
      $self->{'last_code'}   = '0';
      $self->{'last_reason'} = 'Neurio->fetch_Stats_Energy(): \$start and \$granularity are required parameters';
      return 0;
    }
    # make sure that frequqncy is a multiple of 5 if $granularity is in minutes
    if (($granularity eq 'minutes') and defined $frequency) {
      if (eval($frequency%5) != 0) {
        print "\nNeurio->fetch_Stats_Energy(): Only multiples of 5 are supported for \$frequency when \$granularity is in minutes\n\n" if ($self->{'debug'});
      $self->{'last_code'}   = '0';
      $self->{'last_reason'} = 'Neurio->fetch_Stats_Energy(): Only multiples of 5 are supported for \$frequency when \$granularity is in minutes';
        return 0;
      }
    }
    # make sure $granularity is one of the correct values
    if (!($granularity ~~ ['minutes','hours','days','months'])) {
      print "\nNeurio->fetch_Stats_Energy(): Only values of 'minutes, hours, days or months' are supported for \$granularity\n\n" if ($self->{'debug'});
      $self->{'last_code'}   = '0';
      $self->{'last_reason'} = 'Neurio->fetch_Stats_Energy(): Only values of "minutes, hours, days or months" are supported for \$granularity';
      return 0;
    }
    
    my $url = $self->{'Stats_Energy_url'}."&start=$start&granularity=$granularity";
    
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


#******************************************************************************
=head2 fetch_Appliances - Fetch the appliances for a specific location

 Retrieves the appliances added for a specific location.  
 
 The location_id is an optional parameter because it can be specified when 
 connecting.  If it is specified below, then this will over-ride the location 
 ID set when connecting, but for this function call only.

   $Neurio->fetch_Appliances($location_id);

   This method accepts the following parameters:
     - $location_id  : id of a location - Optional
 
 Returns an array of Perl data structures on success
 $VAR1 = [
          {
            'locationId' => 'xxxxxxxxxxxxxxx',
            'name' => 'lighting_appliance',
            'id' => 'yyyyyyyyyyyyyyyyy',
            'label' => 'Range Light on Medium',
            'tags' => []
          },
          {
            'locationId' => 'xxxxxxxxxxxxxxx-3',
            'name' => 'refrigerator',
            'id' => 'zzzzzzzzzzzzzzzz',
            'label' => '',
            'tags' => []
          },
          ....
         ]
 Returns 0 on failure
 
=cut

sub fetch_Appliances {
    my ($self,$location_id) = @_;
    
    # check if $location_id is defined
    if (!defined $location_id) {
      if (!defined $self->{'location_id'}) {
        print "\nNeurio->fetch_Appliances(): \$location_id is a required parameter\n\n" if ($self->{'debug'});
        $self->{'last_code'}   = '0';
        $self->{'last_reason'} = 'Neurio->fetch_Appliances(): \$location_id is a required parameters';
        return 0;
      } else {
        $location_id = $self->{'location_id'};
      }
    }
    my $url = $self->{'Appliances_url'}."?locationId=$location_id";

    return $self->__process_get($url);
}


#******************************************************************************
=head2 fetch_Appliances_Specific - Fetch information about a specific appliance

 Retrieves information about a specific appliance.  
 
 The applicance_id parameter is determined by using the fetch_Appliance method 
 which returns a list of appliances with their IDs

   $Neurio->fetch_Appliances_Specific($appliance_id);

   This method accepts the following parameters:
     - $appliance_id  : id of the appliance - Required
 
 Returns a Perl data structure on success:
 $VAR1 = {
          'locationId' => 'xxxxxxxxxxxxx,
          'name' => 'lighting_appliance',
          'id' => 'yyyyyyyyyyyyyyy',
          'label' => 'Range Light on Medium',
          'tags' => []
        };
 Returns 0 on failure
 
=cut

sub fetch_Appliances_Specific {
    my ($self,$appliance_id) = @_;
    
    # make sure $id is defined
    if (!defined $appliance_id) {
      print "\nNeurio->fetch_Appliances_Specific(): \$appliance_id is a required parameter\n\n" if ($self->{'debug'});
      $self->{'last_code'}   = '0';
      $self->{'last_reason'} = 'Neurio->fetch_Appliances_Specific(): \$appliance_id is a required parameters';
      return 0;
    }

    my $url = $self->{'Appliances_Specific_url'}.$appliance_id;
    
    return $self->__process_get($url);
}


#******************************************************************************
=head2 fetch_Appliances_Stats - Fetch usage data for a given appliance

 Retrieves usage data for a specific appliance at a specific location.  
 
 The applicance_id parameter is determined by using the fetch_Appliance method 
 which returns a list of appliances with their IDs

   $Neurio->fetch_Appliances_Stats($location_id,$appliance_id,$start,$granularity,$end,$frequency,$perPage,$page);

   This method accepts the following parameters:
      - $location_Id  : id of a location - Required
      - $appliance_id : id of the appliance - Required
      - $start         : yyyy-mm-ddThh:mm:ssZ - Required
                        specified using ISO8601 format
      - $granularity   : seconds|minutes|hours|days - Required
      - $end           : yyyy-mm-ddThh:mm:ssZ - Required
                        specified using ISO8601 format
      - $frequency     : an integer - Required
      - $perPage       : number of results per page - Optional
      - $page          : page number to return - Optional
 
 Returns an array of Perl data structures on success
$VAR1 = [
          {
            'energy' => 152927,
            'averagePower' => '110',
            'timeOn' => 1398,
            'guesses' => {},
            'end' => '2014-09-05T14:00:00.000Z',
            'lastEvent' => {
                             'energy' => 74124,
                             'averagePower' => '109',
                             'guesses' => {},
                             'end' => '2014-09-05T13:50:44.055Z',
                             'groupIds' => [
                                             'aaaaaaaaaaaaaaaaa'
                                           ],
                             'id' => '5EGh7o8eQJuIvsdA4qMkEw',
                             'appliance' => {
                                              'locationId' => 'ccccccccccccccccc-3',
                                              'name' => 'refrigerator',
                                              'id' => 'bbbbbbbbbbbbbbbbb',
                                              'label' => '',
                                              'tags' => []
                                            },
                             'start' => '2014-09-05T13:39:20.115Z'
                           },
            'groupIds' => [
                            'aaaaaaaaaaaaaaaaa'
                          ],
            'eventCount' => 2,
            'usagePercentage' => '2.465231',
            'id' => 'ddddddddddddddd',
            'appliance' => {
                             'locationId' => 'ccccccccccccccccc-3',
                             'name' => 'refrigerator',
                             'id' => 'bbbbbbbbbbbbbbbbb',
                             'label' => '',
                             'tags' => []
                           },
            'start' => '2014-09-05T13:00:00.000Z'
          },
          ......
        ]
 Returns 0 on failure
 
=cut

sub fetch_Appliances_Stats {
    my ($self,$location_id,$appliance_id,$start,$granularity,$end,$frequency,$perPage,$page) = @_;
    
    # make sure $location_id is defined
    if (!defined $location_id) {
      print "\nNeurio->fetch_Appliances_Stats(): \$location_id is a required parameter\n\n" if ($self->{'debug'});
      $self->{'last_code'}   = '0';
      $self->{'last_reason'} = 'Neurio->fetch_Appliances_Stats(): \$location_id is a required parameters';
      return 0;
    }
    # make sure $appliance_id is defined
    if (!defined $appliance_id) {
      print "\nNeurio->fetch_Appliances_Stats(): \$appliance_id is a required parameter\n\n" if ($self->{'debug'});
      $self->{'last_code'}   = '0';
      $self->{'last_reason'} = 'Neurio->fetch_Appliances_Stats(): \$appliance_id is a required parameters';
      return 0;
    }
    # make sure $start, $granularity, $end and $frequqncy are defined
    if ((!defined $start) || (!defined $granularity) || (!defined $end) || (!defined $frequency)) {
      print "\nNeurio->fetch_Appliances_Stats(): \$start, \$granularity, \$end and \$frequency are required parameters\n\n" if ($self->{'debug'});
      $self->{'last_code'}   = '0';
      $self->{'last_reason'} = 'Neurio->fetch_Appliances_Stats(): \$start, \$granularity, \$end and \$frequency are required parameters';
      return 0;
    }
    # make sure $granularity is one of the correct values
    if (!($granularity =~ /[seconds|minutes|hours|days]/)) {
      print "\nNeurio->fetch_Appliances_Stats(): Found \$granularity of $granularity\nOnly values of 'seconds, minutes, hours or days' are supported for \$granularity\n\n" if ($self->{'debug'});
      $self->{'last_code'}   = '0';
      $self->{'last_reason'} = 'Neurio->fetch_Appliances_Stats(): Only values of "seconds, minutes, hours or days" are supported for \$granularity';
      return 0;
    }
    
    my $url = $self->{'Appliances_Stats_url'}."?locationId=$location_id&appliance_id=$appliance_id&start=$start&granularity=$granularity&end=$end&frequency=$frequency";
    
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


#******************************************************************************
=head2 fetch_Appliances_Events_by_Location - Fetch events for a specific location

 Retrieves events for a specific location.  An event is an interval when an 
 appliance was in use.
 
 The applicance_id parameter can be determined by using the fetch_Appliance method 
 which returns a list of appliances with their IDs.
 
 The function has the following 2 possibilities for parameters:

   $Neurio->fetch_Appliances_Events_by_Location($location_id, $start,$end,$perPage,$page);
   $Neurio->fetch_Appliances_Events_by_Location($location_id, $since,$perPage,$page);

   This method accepts the following parameters:
      - $location_Id  : id of a location - Required
      - $start        : yyyy-mm-ddThh:mm:ssZ - Required
                        specified using ISO8601 format
      - $end          : yyyy-mm-ddThh:mm:ssZ - Required
                        specified using ISO8601 format
      - $since        : yyyy-mm-ddThh:mm:ssZ - Required
                        specified using ISO8601 format
      - $perPage      : number of results per page - Optional
      - $page         : page number to return - Optional
 
 Returns an array of Perl data structures on success
  [
    {
        "id" : "1cRsH7KQTeONMzjSuRJ2aw",
        "createdAt" : "2014-04-21T22:28:32Z",
        "updatedAt" : "2014-04-21T22:45:32Z",
        "appliance" : {
            "id" : "2SMROBfiTA6huhV7Drrm1g",
            "name" : "television",
            "label" : "upstairs TV",
            "tags" : ["bedroom_television", "42 inch LED"],
            "locationId" : "0qX7nB-8Ry2bxIMTK0EmXw"
        },
        "start" : "2014-04-21T05:26:10.785Z",
        "end" : "2014-04-21T05:36:00.547Z",
        "guesses" : {"dryer1" : 0.78, "dishwasher_2014" : 0.12},
        "energy" : 247896,
        "averagePower" : 122,
        "groupIds" : [ "2pMROafiTA6huhV7Drrm1g", "4SmROBfiTA6huhV7Drrm1h" ],
        "cycleCount" : 5,
        "isRunning" : false
    },
    ...
]
  Returns 0 on failure
 
=cut

sub fetch_Appliances_Events_by_Location {
    my ($self,$location_id,$start,$end,$perPage,$page) = @_;
    my ($url);
    
    # make sure $location_id is defined
    if (!defined $location_id) {
      print "\nNeurio->fetch_Appliances_Events_by_Location(): \$location_id is a required parameter\n\n" if ($self->{'debug'});
      $self->{'last_code'}   = '0';
      $self->{'last_reason'} = 'Neurio->fetch_Appliances_Events_by_Location(): \$location_id is a required parameter';
      return 0;
    }
    # make sure $start (or $since) is defined
    if (!defined $start) {
      print "\nNeurio->fetch_Appliances_Events_by_Location(): \$start is a required parameter\n\n" if ($self->{'debug'});
      $self->{'last_code'}   = '0';
      $self->{'last_reason'} = 'Neurio->fetch_Appliances_Events_by_Location(): \$start is a required parameter';
      return 0;
    }
    
    # check if $end is in ISO8601 format.  If it is, then it is $end.  If not, then $since was specified
    if (defined $end) {
      if (defined eval{DateTime::Format::ISO8601->parse_datetime($end)}) {
        $url = $self->{'Appliances_Events_url'}."?locationId=$location_id&start=$start&end=$end";
      } else {
        $perPage = $end;
        $page    = $perPage;
        $url     = $self->{'Appliances_Events_url'}."?locationId=$location_id&since=$start";
      }
    } else {
      $url = $self->{'Appliances_Events_url'}."?locationId=$location_id&since=$start";
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


#******************************************************************************
=head2 fetch_Appliances_Events_by_Appliance - Fetch events for a specific appliance

 Retrieves events for a specific appliance.  An event is an interval when an 
 appliance was in use.
 
 The applicance_id parameter can be determined by using the fetch_Appliance method 
 which returns a list of appliances with their IDs.
 
   $Neurio->fetch_Appliances_Events_by_Appliance($appliance_id,$start,$end,$perPage,$page);

   This method accepts the following parameters:
      - $appliance_id : id of the appliance - Required
      - $start        : yyyy-mm-ddThh:mm:ssZ - Required
                        specified using ISO8601 format
      - $end          : yyyy-mm-ddThh:mm:ssZ - Required
                        specified using ISO8601 format
      - $since        : yyyy-mm-ddThh:mm:ssZ - Required
                        specified using ISO8601 format
      - $perPage      : number of results per page - Optional
      - $page         : page number to return - Optional
 
 Returns an array of Perl data structures on success
 [
    {
        "id" : "1cRsH7KQTeONMzjSuRJ2aw",
        "createdAt" : "2014-04-21T22:28:32Z",
        "updatedAt" : "2014-04-21T22:45:32Z",
        "appliance" : {
            "id" : "2SMROBfiTA6huhV7Drrm1g",
            "name" : "television",
            "label" : "upstairs TV",
            "tags" : ["bedroom_television", "42 inch LED"],
            "locationId" : "0qX7nB-8Ry2bxIMTK0EmXw"
        },
        "start" : "2014-04-21T05:26:10.785Z",
        "end" : "2014-04-21T05:36:00.547Z",
        "guesses" : {"dryer1" : 0.78, "dishwasher_2014" : 0.12},
        "energy" : 247896,
        "averagePower" : 122,
        "groupIds" : [ "2pMROafiTA6huhV7Drrm1g", "4SmROBfiTA6huhV7Drrm1h" ],
        "cycleCount" : 5,
        "isRunning" : false
    },
    ...
 ]
 Returns 0 on failure
 
=cut

sub fetch_Appliances_Events_by_Appliance {
    my ($self,$appliance_id,$start,$end,$perPage,$page) = @_;
    
    # make sure $appliance_id is defined
    if (!defined $appliance_id) {
      print "\nNeurio->fetch_Appliances_Events_by_Appliance(): \$appliance_id is a required parameter\n\n" if ($self->{'debug'});
      $self->{'last_code'}   = '0';
      $self->{'last_reason'} = 'Neurio->fetch_Appliances_Events_by_Appliance(): \$appliance_id is a required parameters';
      return 0;
    }
    # make sure $start and $end are defined
    if ((!defined $start) || (!defined $end)) {
      print "\nNeurio->fetch_Appliances_Events_by_Appliance(): \$start and \$end are required parameters\n\n" if ($self->{'debug'});
      $self->{'last_code'}   = '0';
      $self->{'last_reason'} = 'Neurio->fetch_Appliances_Events_by_Appliance(): \$start and \$end are required parameters';
      return 0;
    }

    my $url = $self->{'Appliances_Events_url'}."?applianceId=$appliance_id&start=$start&end=$end";
    
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


#******************************************************************************
=head2 dump_Object - shows the contents of the local Neurio object

 shows the contents of the local Neurio object in human readable form

   $Neurio->dump_Object();

   This method accepts no parameters
 
 Returns nothing
 
=cut

sub dump_Object {
    my $self  = shift;
    
    print "Key                     : ".substr($self->{'key'},                      0,120)."\n";
    print "SecretKey               : ".substr($self->{'secret'},                   0,120)."\n";
    print "Sensor_ID               : ".substr($self->{'sensor_id'},                0,120)."\n";
    print "Location_ID             : ".substr($self->{'location_id'},              0,120)."\n";
    print "Access_token            : ".substr($self->{'access_token'},             0,120)."\n";
    print "Base 64                 : ".substr($self->{'base64'},                   0,120)."\n";
    print "Base URL                : ".substr($self->{'base_url'},                 0,120)."\n";
    print "Samples_Recent_Live URL : ".substr($self->{'Samples_Recent_Live_url'},  0,120)."\n";
    print "Samples_Last_Live URL   : ".substr($self->{'Samples_Last_Live_url'},    0,120)."\n";
    print "Samples URL             : ".substr($self->{'Samples_url'},              0,120)."\n";
    print "Samples_Full URL        : ".substr($self->{'Samples_Full_url'},         0,120)."\n";
    print "Stats_Energy URL        : ".substr($self->{'Stats_Energy_url'},         0,120)."\n";
    print "Appliances URL          : ".substr($self->{'Appliances_url'},           0,120)."\n";
    print "Appliances_Specific URL : ".substr($self->{'Appliances_Specific_url'},  0,120)."\n";
    print "Appliances_Stats URL    : ".substr($self->{'Appliances_Stats_url'},     0,120)."\n";
    print "Appliances_Events URL   : ".substr($self->{'Appliances_Events_url'},    0,120)."\n";
    print "debug                   : ".substr($self->{'debug'},                    0,120)."\n";
    print "last_code               : ".substr($self->{'last_code'},                0,120)."\n";
    print "last_reason             : ".substr($self->{'last_reason'},              0,120)."\n";
    print "\n";
}


#******************************************************************************
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

#******************************************************************************
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

#******************************************************************************
sub __process_get {
    my $self     = shift;
    my $url      = shift;
	my $response = $self->{'ua'}->get($url,"Authorization"=>"Bearer ".$self->{'access_token'});

    $self->{'last_code'} = $response->code;

    if (($response->code) eq '200') {
      $self->{'last_reason'} = '';
    } else {
      $self->{'last_reason'} = $response->message;
    }

    if ($response->is_success) {
      return decode_json($response->content);
    } else {
      print "\n".(caller(1))[3]."(): Failed with return code ".$self->get_last_code()." - ".$self->get_last_reason()."\n" if ($self->{'debug'});
      return 0;
    }
}

#******************************************************************************
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

#******************************************************************************
1; # End of Device::Neurio - Return success to require/use statement
#******************************************************************************


