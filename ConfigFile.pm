#
#       ConfigFile.pm
#
#       Copyright 2011 Philipp Böhm <philipp-boehm@live.de>
#
#       This program is free software; you can redistribute it and/or modify
#       it under the terms of the GNU General Public License as published by
#       the Free Software Foundation; either version 2 of the License, or
#       (at your option) any later version.
#
#       This program is distributed in the hope that it will be useful,
#       but WITHOUT ANY WARRANTY; without even the implied warranty of
#       MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#       GNU General Public License for more details.
#
#       You should have received a copy of the GNU General Public License
#       along with this program; if not, write to the Free Software
#       Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
#       MA 02110-1301, USA.
#
#       Klasse, die die Verarbeitung der Konfiguration kapselt
#

package Utils::ConfigFile;

use Moose;
use Config::IniFiles;

has 'configdir'  => ( is => 'ro', isa => 'Str',     required => 1, );
has 'configfile' => ( is => 'ro', isa => 'Str',     required => 1, );
has 'directives' => ( is => 'rw', isa => 'HashRef', required => 1, );
has 'section' => ( is => 'ro', isa => 'Str', default => 'configuration' );
has 'cfg' => ( is => 'rw', isa => 'Config::IniFiles', lazy_build => 1 );

sub getConfig {
    ###
    # Liefert die verarbeitete Config zurück
    my ($self) = @_;
    $self->_setup_environment();
    $self->_process_configfile();

    return $self->directives;
}

sub _setup_environment {
    ###
    # Erstellt den Pfad zur Datei und die Datei selber
    my ($self) = @_;

    if ( !-d $self->configdir ) {
        mkdir( $self->configdir ) or die "Konnte CONFIGDIR nicht anlegen";
    }

    if ( !-f $self->configfile ) {
        open( FILE, "+>", $self->configfile )
          or die "Konnte CONFIGFILE nicht anlegen";
        close(FILE);
    }

}

sub _build_cfg {
    Config::IniFiles->new();
}

sub _process_configfile {
    ###
    # Verarbeitet die Werte in der ini-Datei und schreibt unterschiedliche Werte
    # in die Config
    my ($self) = @_;

    $self->cfg->SetFileName( $self->configfile );
    $self->cfg->ReadConfig();

    $self->cfg->AddSection( $self->section )
      unless $self->cfg->SectionExists( $self->section );

    for my $key ( keys %{ $self->directives } ) {
        my $value = $self->directives->{$key};
        my $existing_value = $self->cfg->val( $self->section, $key );

        if ( !$existing_value ) {
            $self->cfg->newval( $self->section, $key, $value );
        }
        else {
            if ( $self->directives->{$key} ne $existing_value ) {
                $self->directives->{$key} = $existing_value;
            }
        }
    }
    $self->cfg->RewriteConfig();
}

1;
