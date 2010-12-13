#!/usr/bin/perl
use strictures 1;

use Test::More;
use Carp;
use Devel::Dwarn;

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

  sub _ssh_env_vars {
    $_[0]->{ssh_env_vars} ||= $_[0]->_build_ssh_env_vars;
  }

  sub _build_ssh_env_vars {
    return '';
    # this needs work I think. First off, it won't work.
    # +{ $_[0]->_firsthop_perlssh->eval(; 'chomp(my @env = `ssh-agent`); my %new_env; foreach (@env) { /^(.*?)=(.*)/; $ENV{$1} =$new_env{$1}=$2; } return %new_env;' ); }
  }

  sub _open_perlssh {
    my( $self, @hosts ) = @_;
    my $ssh = $self->_ssh;

    my $env_str = $self->_ssh_env_vars;
    my $command = join ' ', (map "ssh -o StrictHostKeyChecking=no -A $_", @hosts), "perl";
    $command = "sh -c '$env_str$command'"; 
    my( $read, $write ) = $ssh->open2($command);

    my $readfunc = sub { sysread( $read, $_[0], $_[1] ) };
    my $writefunc = sub { syswrite( $write, $_[0] ) };
    
    ($command, IPC::PerlSSH->new( Readfunc => $readfunc, Writefunc => $writefunc ));
  }


}

my $ssh = Net::SSH::Perl->new('localhost');
$ssh->login('test', 'test');

my $pipc = Net::SSH::Perl::ProxiedIPC->new(ssh => $ssh);

my ($cmd, $perlssh) = $pipc->_open_perlssh;

is( ref $perlssh, "IPC::PerlSSH", "\$perlssh isa IPC::PerlSSH (via $cmd)" );

$perlssh->eval( "use POSIX qw(uname)" );
my @remote_uname = $perlssh->eval( "uname()" );

## This is a really shitty idea for a test but fuck you.
is( $remote_uname[1], "minerva", 'localhost uname() returns minerva' );

my $homedir = $perlssh->eval( '$ENV{HOME}' );
fail( "we require a little sensibility in our \$ENV thank you." )
  unless defined $homedir;

$perlssh->eval( "use File::HomeDir" );
my $homedir2 = $perlssh->eval( 'File::HomeDir->my_home' );
is( $homedir2, "/home/test", 'got $ENV{HOME} the smart way' );

my $new_env = $perlssh->eval( 'chomp(my @env = `ssh-agent`); my %new_env; foreach (@env) { /^(.*?)=([^;]+)/ or next; $ENV{$1} =$new_env{$1}=$2; } my $output; $output .= "$_=$new_env{$_} " foreach ( keys %new_env ); $output;' );
Dwarn $new_env;
$pipc->{ssh_env_vars} = $new_env; 

my @test_hosts = ( 'stagetwo@localhost', 'stagethree@localhost' );
my ($cmd2, $pssh2) = $pipc->_open_perlssh(@test_hosts);
is( ref $pssh2, "IPC::PerlSSH", "\$pssh2 isa IPC::PerlSSH (via $cmd2)" );

$pssh2->eval( "use POSIX qw(uname)" );
@remote_uname = $pssh2->eval( "uname()" );
is( $remote_uname[1], "minerva", 'uname() returns minerva three jumps into localhost!' );

done_testing;
