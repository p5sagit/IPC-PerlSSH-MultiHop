package IPC::PerlSSH::MultiHop;

use strict;
use warnings;
use IPC::PerlSSH;
use IPC::Open2 qw(open2);

sub new {
  my $proto = shift;
  my $class = ref $proto || $proto;
  bless( { @_ }, $class );
}

sub _firsthop_ssh { $_[0]->{firsthop_ssh} }

sub _firsthop_perlssh {
  $_[0]->{firsthop_perlssh} ||= $_[0]->_build_firsthop_perlssh;
}

sub _build_firsthop_perlssh {
  my ($self) = @_;
  $self->_construct_perlssh($self->_firsthop_ssh->open2('perl'));
}

sub _hop_hosts { $_[0]->{hop_hosts} }

sub _ssh_auth_env {
  $_[0]->{ssh_auth_env} ||= $_[0]->_build_ssh_auth_env;
}

sub _build_ssh_auth_env {
  my ($self) = @_;
  if (!$self->_firsthop_ssh and my $env = $ENV{SSH_AUTH_SOCK}) {
    "SSH_AUTH_SOCK=${env}";
  } else {
    my $all_env = $self->_construct_ssh_env_vars;
    my ($env) = ($all_env =~ /^(SSH_AUTH_SOCK=(?:[^;]+));/);
    $env;
  }
}

sub _construct_ssh_env_vars {
  my ($self) = @_;
  if ($self->_firsthop_ssh) {
    $self->_firsthop_perlssh->eval(
      'my $env = `ssh-agent`; `$env\n ssh-add`; $env;'
    );
  } else {
    my $env = `ssh-agent`; system(qq{$env\n ssh-add}); $env;
  }
}

sub _final_perlssh { $_[0]->{final_perlssh} ||= $_[0]->_build_final_perlssh }

sub _build_final_perlssh {
  my ($self) = @_;
  my @hosts = @{$self->_hop_hosts};

  my $env_str = $self->_ssh_auth_env;
  my $command = join ' ',
    $env_str,
    (map "ssh -o StrictHostKeyChecking=no -A $_", @hosts),
    "perl";
  $self->_construct_perlssh($self->_open2($command));
}

sub _construct_perlssh {
  my ($self, $read, $write) = @_;
  my $readfunc = sub { sysread( $read, $_[0], $_[1] ) };
  my $writefunc = sub { syswrite( $write, $_[0] ) };
  
  IPC::PerlSSH->new( Readfunc => $readfunc, Writefunc => $writefunc );
}

sub _open2 {
  my ($self, $command) = @_;
  if (my $ssh = $self->_firsthop_ssh) {
    $ssh->open2($command);
  } else {
    open2(my $readpipe, my $writepipe, $command)
      or die "Failed to open ${command}: $!";
    ($readpipe, $writepipe);
  }
}

sub eval {
  my ($self, @args) = @_;
  $self->_final_perlssh->eval(@args)
}

1;
