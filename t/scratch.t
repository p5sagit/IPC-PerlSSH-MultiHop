#!/usr/bin/perl
use strictures 1;

use Test::More;

{
  package Net::SSH::Perl::ProxiedIPC;
  use strict; use warnings;
  use Net::SSH::Perl::WithSocks;
  use IPC::PerlSSH;

  sub new {
    my $proto = shift;
    my $class = ref $proto || $proto;
    bless( { @_ }, $class );
  }

  sub _ssh {
    $_[0]->{ssh} ||= $_[0]->_build_ssh
  }

  sub _build_ssh {
    Net::SSH::Perl::WithSocks->new();
  }

  sub _open_perlssh {
    my( $self, @hosts ) = @_;
    my $ssh = $self->_ssh;
    my $command = join ' ', (map "ssh -A $_", @hosts), "perl";
    my( $read, $write ) = $ssh->open2($command);

    my $readfunc = sub { sysread( $read, $_[0], $_[1] ) };
    my $writefunc = sub { syswrite( $write, $_[0] ) };
    
    IPC::PerlSSH->new( Readfunc => $readfunc, Writefunc => $writefunc );
  }


}

my $ssh = Net::SSH::Perl->new('localhost');
$ssh->login('test', 'test');

my $pipc = Net::SSH::Perl::ProxiedIPC->new(ssh => $ssh);

my $perlssh = $pipc->_open_perlssh;

is( ref $perlssh, "IPC::PerlSSH", '$perlssh isa IPC::PerlSSH' );

$perlssh->eval( "use POSIX qw(uname)" );
my @remote_uname = $perlssh->eval( "uname()" );

## This is a really shitty idea for a test but fuck you.
is( $remote_uname[1], "minerva", 'localhost uname() returns minerva' );
done_testing;
