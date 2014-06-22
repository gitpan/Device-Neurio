package Neurio;

use warnings;
use strict;

BEGIN
{
  if ($^O eq "MSWin32"){
    print "Need to specify windows imports\n";
    exit(-1);
  } else {
    use LWP::UserAgent;
    use JSON qw( decode_json );
    use MIME::Base64 (qw(encode_base64));
    use Data::Dumper;
  }
}

=head1 NAME

Device::Neurio - Methods for accessing data collected by a Neurio sensor module.

=head1 VERSION

Version 0.05

=cut

our $VERSION = '0.05';

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

 The module is written entirely in Perl and has been tested on Raspbian Linux.

 Here is some sample code:

    use Device::Neurio;

    my $Neurio = Device::Neurio->new($key,$secret,$sensor_id);

    $Neurio->connect();
  
    $data = $my_Neurio->fetch_Last_Live();
    $data = $my_Neurio->fetch_Recent_Live();
    $data = $my_Neurio->fetch_Recent_Live("2014-06-18T19:20:21Z");

    print Dumper($data);

    undef $Neurio;

=head1 SUBROUTINES/METHODS

=head2 new - the constructor for a Neurio object.

 Creates a new instance to fetch data for a unique Neurio sensor.

 my $Neurio = Device::Neurio->new($key,$secret,$sensor_id);

   This method accepts the following parameters:
     - $key       : unique key for the account - Required parameter
     - $secret    : secret key for the account - Required parameter
     - $sensor_id : sensor ID connected to the account - Required parameter

 The Object is returned if successful.
 If one or more parameters is omitted, 0 is returned to indicate failure.
=cut

sub new {
    my $class = shift;
    my $self;

    $self->{'ua'}        = LWP::UserAgent->new();
    $self->{'key'}       = shift;
    $self->{'secret'}    = shift;
    $self->{'sensor_id'} = shift;
    $self->{'base64'}    = encode_base64($self->{'key'}.":".$self->{'secret'});
    chomp($self->{'base64'});
    
    if ((!defined $self->{'key'}) || (!defined $self->{'secret'}) || (!defined $self->{'sensor_id'})) {
      print "Key, Secret and Sensor ID are REQUIRED parameters\n";
      return 0;
    }
    
    bless $self, $class;
    
    return $self;
}

#*****************************************************************

=head2 connect - open a secure connection to the Neurio server.

 Opens a secure connection via HTTPS to the Neurio server which provides
 access to a set of API commands to access the sensor data.

   $Neurio->connect();
 
 This method accepts no parameters
 
 Returns 1 on success and 0 on failure.
=cut

sub connect {
	my $self         = shift;
	my $access_token = '';
	
    # Submit request for authentiaction token.
    my $response = $self->{'ua'}->post( 'https://api-staging.neur.io/v1/oauth2/token',  
          { basic_authentication =>  $self->{'base64'},
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
      print "Failed to connect\n";
      return 0;
    }
}

#*****************************************************************

=head2 fetch_Recent_Live - Fetch recent sensor samples

 Retrieves recent sensor readings from the Neurio server.

   $Neurio->fetch_Recent_Live($last);
 
   This method accepts the following parameters:
      $last - yyyy-mm-ddThh:mm:ssZ - Optional parameter
 
 Return value is a Perl data structure containing all the raw data
=cut

sub fetch_Recent_Live {
    my ($self,$last) = @_;
    my ($url,$response,$decoded_response);
    
    if (defined $last) {
      $url = "https://api-staging.neur.io/v1/samples/live?sensorId=".$self->{'sensor_id'}."&last=$last";
    } else {
      $url = "https://api-staging.neur.io/v1/samples/live?sensorId=".$self->{'sensor_id'};
    }
    $response         = $self->{'ua'}->get($url,"Authorization"=>"Bearer ".$self->{'access_token'});
    $decoded_response = decode_json($response->content);

    return $decoded_response;
}


#*****************************************************************

=head2 fetch_Last_Live - Fetch the last live sensor sample

 Retrieves the last live sensor reading from the Neurio server.  

   $Neurio->fetch_Last_Live();

   This method accepts no parameters
 
 Return value is a Perl data structure containing all the raw data
=cut

sub fetch_Last_Live {
    my $self             = shift;
    my ($url,$response,$decoded_response);
    
    $url              = "https://api-staging.neur.io/v1/samples/live/last?sensorId=".$self->{'sensor_id'};
	$response         = $self->{'ua'}->get($url,"Authorization"=>"Bearer ".$self->{'access_token'});
    $decoded_response = decode_json($response->content);
     
    return $decoded_response;
}

#*****************************************************************

=head2 fetch_Samples - Fetch sensor samples from the Neurio server.

 Retrieves sensor readings within the parameters specified.

 $Neurio->fetch_Samples($start,$granularity,$end,$frequency);

   This method accepts the following parameters:
     - start       : yyyy-mm-ddThh:mm:ssZ - Required
     - granularity : seconds|minutes|hours|days - Required
     - end         : yyyy-mm-ddThh:mm:ssZ - Optional
     - freqnecy    : an integer - Optional
 
 Return value is a Perl data structure containing all the raw data
 On failure, 0 is returned
=cut

sub fetch_Samples {
    my ($self,$start,$granularity,$end,$frequency) = @_;
    my ($url,$response,$decoded_response);
    
    $url = "https://api-staging.neur.io/v1/samples?sensorId=".$self->{'sensor_id'}."&start=$start&granularity=$granularity";
    
    if ((!defined $start) || (!defined $granularity)) {
      print "Start and Granularity are required parameters\n";
      return 0;
    }
    if (defined $end) {
      $url = $url . "&end=$end";
    }
    if (defined $frequency) {
      $url = $url . "&frequency=$frequency";
    }
    
	$response         = $self->{'ua'}->get($url,"Authorization"=>"Bearer ".$self->{'access_token'});
    $decoded_response = decode_json($response->content);
     
    return $decoded_response;
}

#*****************************************************************

=head2 fetch_Full_Samples - Fetches full samples for all phases.

 Retrieves full sensor readings including all phases within the parameters 
 specified.

 $Neurio->fetch_Full_Samples($start,$granularity,$end,$frequency);

   This method accepts the following parameters:
     - start       : yyyy-mm-ddThh:mm:ssZ - Required
     - granularity : seconds|minutes|hours|days - Required
     - end         : yyyy-mm-ddThh:mm:ssZ - Optional
     - freqnecy    : an integer - Optional
 
 Return value is a Perl data structure containing all the raw data
 On failure, 0 is returned
=cut

sub fetch_Full_Samples {
    my ($self,$start,$granularity,$end,$frequency) = @_;
    my ($url,$response,$decoded_response);
    
    $url = "https://api-staging.neur.io/v1/samples/full?sensorId=".$self->{'sensor_id'}."&start=$start&granularity=$granularity";

    if ((!defined $start) || (!defined $granularity)) {
      print "Start and Granularity are required parameters\n";
      return 0;
    }
    if (defined $end) {
      $url = $url . "&end=$end";
    }
    if (defined $frequency) {
      $url = $url . "&frequency=$frequency";
    }
    
	$response         = $self->{'ua'}->get($url,"Authorization"=>"Bearer ".$self->{'access_token'});
    $decoded_response = decode_json($response->content);
     
    return $decoded_response;
}

#*****************************************************************

=head2 fetch_Energy_Stats - Fetches energy statistics.

 Retrieves energy statistics within the parameters specified.

   $Neurio->fetch_Energy_Stats($start,$granularity,$end,$frequency);

   This method accepts the following parameters:
     - start       : yyyy-mm-ddThh:mm:ssZ - Required
     - granularity : seconds|minutes|hours|days - Required
     - end         : yyyy-mm-ddThh:mm:ssZ - Optional
     - freqnecy    : an integer - Optional
 
 Return value is a Perl data structure containing all the raw data
 On failure, 0 is returned
=cut

sub fetch_Energy_Stats {
    my ($self,$start,$granularity,$end,$frequency) = @_;
    my ($url,$response,$decoded_response);

    $url = "https://api-staging.neur.io/v1/samples/stats?sensorId=".$self->{'sensor_id'}."&start=$start&granularity=$granularity";

    if ((!defined $start) || (!defined $granularity)) {
      print "Start and Granularity are required parameters\n";
      return 0;
    }
    if (defined $end) {
      $url = $url . "&end=$end";
    }
    if (defined $frequency) {
      $url = $url . "&frequency=$frequency";
    }

	$response         = $self->{'ua'}->get($url,"Authorization"=>"Bearer ".$self->{'access_token'});
    $decoded_response = decode_json($response->content);
     
    return $decoded_response;
}


#*****************************************************************

=head1 AUTHOR

Kedar Warriner, C<kedarwarriner at gmail.com>

=head1 BUGS

 Please report any bugs or feature requests to C<bug-device-Neurio at rt.cpan.org>
 or through the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Device-Neurio>
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

 Copyright 2014 Kedar Warriner.

 This program is free software; you can redistribute it and/or modify it
 under the terms of either: the GNU General Public License as published
 by the Free Software Foundation; or the Artistic License.

 See http://dev.perl.org/licenses/ for more information.


=cut

#********************************************************************
1; # End of Device::Neurio - Return success to require/use statement
#********************************************************************

