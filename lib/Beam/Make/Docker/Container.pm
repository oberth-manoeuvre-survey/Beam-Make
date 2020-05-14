package Beam::Make::Docker::Container;
our $VERSION = '0.002';
# ABSTRACT: A Beam::Make recipe to build a Docker container

=head1 SYNOPSIS

    ### Beamfile
    convos:
        $class: Beam::Make::Docker::Container
        image: nordaaker/convos:latest
        restart: unless-stopped
        ports:
            - 8080:3000
        volumes:
            - $HOME/convos/data:/data

=head1 DESCRIPTION

This L<Beam::Make> recipe class creates a Docker container, re-creating
it if the underlying image has changed.

B<NOTE:> This works for basic use-cases, but could use some
improvements. Improvements should attempt to match the C<docker-compose>
file syntax when possible.

=head1 SEE ALSO

L<Beam::Make::Docker::Image>, L<Beam::Make>, L<https://docker.com>

=cut

use v5.20;
use warnings;
use autodie qw( :all );
use Moo;
use Time::Piece;
use Log::Any qw( $LOG );
use File::Which qw( which );
use JSON::PP qw( decode_json );
use Digest::SHA qw( sha1_base64 );
use experimental qw( signatures postderef );

extends 'Beam::Make::Recipe';

=attr image

The image to use for this container. Required.

=cut

has image => (
    is => 'ro',
    required => 1,
);

=attr command

The command to run, overriding the image's default command.

=cut

has command => (
    is => 'ro',
);

=attr volumes

A list of volumes to map. Volumes are strings with the local volume or
Docker named volume and the destination mount point separated by a C<:>.

=cut

has volumes => (
    is => 'ro',
);

=attr ports

A list of ports to map. Ports are strings with the local port and the
destination port separated by a C<:>.

=cut

has ports => (
    is => 'ro',
);

=attr environment

The environment variables to set in this container. A list of C<< NAME=VALUE >> strings.

=cut

has environment => (
    is => 'ro',
);

=attr restart

The restart policy for this container. One of C<no>, C<on-failure>,
C<always>, C<unless-stopped>.

=cut

has restart => (
    is => 'ro',
);

=attr docker

The path to the Docker executable to use. Defaults to looking up
C<docker> in C<PATH>.

=cut

has docker => (
    is => 'ro',
    default => sub { which 'docker' },
);

sub make( $self, %vars ) {
    my @cmd = (
        $self->docker, qw( container create ),
        '--name' => $self->name,
        ( $self->restart ? ( '--restart' => $self->restart ) : () ),
        ( $self->environment ? map {; "-e", $_ } $self->environment->@* : () ),
        ( $self->ports ? map {; "-p", $_ } $self->ports->@* : () ),
        ( $self->volumes ? map {; "-v", $_ } $self->volumes->@* : () ),
        $self->image,
        $self->command,
    );
    $LOG->debug( 'Running docker command:', @cmd );
    system @cmd;
    delete $self->{_inspect_output} if exists $self->{_inspect_output};
    return 0;
}

sub _container_info( $self ) {
    state $json = JSON::PP->new->canonical->utf8;
    my $output = $self->{_inspect_output};
    if ( !$output ) {
        my $cmd = join ' ', $self->docker, qw( container inspect ), $self->name;
        $LOG->debug( 'Running docker command:', $cmd );
        $output = `$cmd`;
        $self->{_inspect_output} = $output;
    }
    my ( $container ) = $json->decode( $output )->@*;
    return $container || {};
}

sub _cache_hash( $self ) {
    my $json = JSON::PP->new->canonical->utf8;
    my $container = $self->_container_info;
    return unless keys %$container;
    return $container->{Id};
}

sub last_modified( $self ) {
    my $container = $self->_container_info;
    return 0 unless keys %$container;
    my $created = $container->{Created} =~ s/^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}).*/$1/r;
    my $iso8601 = '%Y-%m-%dT%H:%M:%S';
    return Time::Piece->strptime( $created, $iso8601 );
}

1;

