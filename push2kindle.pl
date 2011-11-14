#!/usr/bin/perl -w

#       push2kindle.pl
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
#       Tool sendet Files per Email zum Kindle, von einer Gmail-Adresse
#

use strict;
use Readonly;
use Getopt::Long;
use Email::Send;
use MIME::Lite;
use Archive::Zip qw( :ERROR_CODES :CONSTANTS );
use File::Spec::Functions qw/catfile/;
use File::Basename;
use File::Copy;
use File::stat;
use File::Path qw(remove_tree);

chdir( dirname($0) );
require ConfigFile;

Readonly my $VERSION       => "0.0.2";
Readonly my $MAX_FILE_SIZE => 52428800;    # 50MB

################################################################################
############### Konfiguration laden ############################################
################################################################################
my $PROG_CONFIGDIR  = catfile( $ENV{"HOME"},    ".push2kindle" );
my $PROG_CONFIGFILE = catfile( $PROG_CONFIGDIR, "config.ini" );

my $ConfigFile = Utils::ConfigFile->new(
    configdir  => $PROG_CONFIGDIR,
    configfile => $PROG_CONFIGFILE,
    directives => {
        "queuedirectory"        => "",
        "gmail_accountname"     => "",
        "gmail_accountpassword" => "",
        "kindle_addresses"      => "",
        "unsupported_directory" =>
          catfile( $PROG_CONFIGDIR, "unsupported_files" ),
    },
);
my %CONF = %{ $ConfigFile->getConfig() };

################################################################################
############### Parameter erfassen #############################################
################################################################################
my @KINDLES;
my @EXPLICIT_FILES;

my %PARAMS = ();
GetOptions(
    \%PARAMS,
    "help"    => \&help,
    "version" => sub { print $VERSION . "\n"; exit; },
    "verbose",
    "queuedirectory=s",
    "to=s"   => \@KINDLES,
    "file=s" => \@EXPLICIT_FILES,
);

die "Sie müssen Ihre Gmail-Zugangsdaten angeben"
  unless ( $CONF{"gmail_accountname"} && $CONF{"gmail_accountpassword"} );

die "Sie müssen ein existierendes Queue-Verzeichnis übergeben"
  unless ( defined $CONF{"queuedirectory"}
    && -d $CONF{"queuedirectory"} );

die "Sie müssen ein Verzeichnis für falsche Dateien übergeben"
  unless defined $CONF{"unsupported_directory"};

mkdir( $CONF{"unsupported_directory"} )
  unless -d $CONF{"unsupported_directory"};

#######
# Kindle-Adressen aus Config extrahieren falls nicht explizit als
# Parameter angegeben
if ( scalar @KINDLES == 0 ) {
    @KINDLES = split /[,;]/, $CONF{"kindle_addresses"};
}

die "Keine Email-Adressen gefunden, an die Daten verschickt werden könnten"
  if ( scalar @KINDLES < 1 );

################################################################################
################# Explizit angegebene Dateien einbeziehen ######################
################################################################################
for my $file (@EXPLICIT_FILES) {
    next unless -f $file;
    printf "Füge '%s' hinzu\n", $file;
    copy( $file, $CONF{"queuedirectory"} );
}

################################################################################
##### Dateien in Queue verarbeiten und für den Versand unterteilen #############
################################################################################
chdir( $CONF{"queuedirectory"} );

my $current_full_size     = 0;
my $current_zip_directory = "transfer_" . time();

opendir( my $DIR, "." ) or die "Konnte Verzeichnis nicht öffnen";
while ( my $file = readdir($DIR) ) {
    next if ( $file eq '.' || $file eq '..' || -d $file );

    my $file_size = stat($file)->size;

    ######
    # Wenn Dateien nicht unterstützt oder > 50MB dann verschieben
    if (   $file !~ /\.(pdf|doc|docx|rtf|htm|html|txt|mobi|jpg|png|bmp)$/
        || $file_size >= $MAX_FILE_SIZE )
    {
        printf "'%s' wird nicht unterstützt oder ist zu groß", $file;
        move( $file, catfile( $CONF{"unsupported_directory"}, $file ) )
          or die "Fehler beim Verschieben der Datei $file";
        next;
    }

    ######
    # Wenn aktuelle Datei den einen Ordner sprengen würde neuen anlegen
    if ( ( $current_full_size + $file_size ) >= $MAX_FILE_SIZE ) {
        $current_full_size = 0;
        sleep 1;
        $current_zip_directory = "transfer_" . time();
    }

    mkdir($current_zip_directory) unless -d $current_zip_directory;

    ####
    # Datei verschieben
    move( $file, catfile( $current_zip_directory, $file ) )
      or die "Konnte Datei nicht in ZIP-Verzeichnis verschieben";
    $current_full_size += $file_size;
}
close($DIR);

################################################################################
############### Verzeichnisse für den Versand zippen ###########################
################################################################################

opendir( $DIR, "." ) or die "Konnte Verzeichnis nicht öffnen";
while ( my $directory = readdir($DIR) ) {
    next if ( $directory eq '.' || $directory eq '..' || -f $directory );

    if ( my ($directory_id) = $directory =~ /transfer_(\d+)/ ) {

        chdir($directory);
        my $zip = Archive::Zip->new();
        for my $file ( glob "*" ) {
            $zip->addFile($file);
        }
        ( $zip->writeToFileNamed( catfile( "..", $directory_id . '.zip' ) ) ==
              AZ_OK )
          or die "Konnte $directory nicht zippen";

        chdir("..");
        remove_tree($directory);
    }
}

################################################################################
######### Verbindung zu Server aufbauen und Dateien senden #####################
################################################################################
my $mailer = Email::Send->new(
    {
        mailer      => 'Gmail',
        mailer_args => [
            username => $CONF{"gmail_accountname"},
            password => $CONF{"gmail_accountpassword"},
        ]
    }
) or die "Konnte keine Verbindung zu GMail aufbauen";

for my $zipfile ( glob "*.zip" ) {

    for my $kindle_address (@KINDLES) {

        printf "Sende %s per Email an %s\n", $zipfile, $kindle_address;

        my $msg = MIME::Lite->new(
            From    => $CONF{"gmail_accountname"},
            To      => $kindle_address,
            Subject => 'push2kindle-File-Transfer - ' . time(),
            Data =>
              'Diese Email enthält ein Zip-Archiv mit aktuellen Dokumenten'
        );

        $msg->attach(
            Type        => 'application/zip',
            Path        => $zipfile,
            Filename    => $zipfile,
            Disposition => "attachment"
        );

        eval { $mailer->send( $msg->as_string ) };
        die "Error sending email: $@" if $@;
    }
    unlink($zipfile);
}

################################################################################
############## Funktionsdefinitionen ###########################################
################################################################################

sub help {
    print << "EOF";

Copyright 2011 Philipp Böhm

Dieses Script sendet Files per Email (Google Mail) an einen Kindle.
    
Usage: $0 [Optionen]

   --help               : Diesen Hilfetext ausgeben
   --verbose            : erweiterte Ausgaben
   --version            : Versionshinweis
   --queuedirectory=DIR : Verzeichnis, in denen nach Dateien gesucht wird, die
                          an den Kindle übertragen werden können
   --to=EMAIL-ADDRESS   : Adresse eines Kindles (kann öfters angegeben werden)
   --file=FILE          : Datei, außerhalb des Queue-Verzeichnis, wird ebenfalls
                          an den Kindle geschickt (kann öfters angegeben werden) 
                   
EOF
    exit();
}
