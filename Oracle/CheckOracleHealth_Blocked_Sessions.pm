use Data::Dumper;

package MySession::blocked;

use strict;

our @ISA = qw(MySession);

{
  my @blocked_sessions = ();
  my $initerrors = undef;
 
  sub add_blocked_session {
    push(@blocked_sessions, shift);
  }
  
  sub return_blocked_sessions {
    return @blocked_sessions;
  }
  
  sub init_blocked_sessions {
    my %params = @_;
    my $num_blocked_sessions = 0;
	
    my @blocked_sessionresult = ();
    @blocked_sessionresult = $params{handle}->fetchall_array(q{
		SELECT 
			b.inst_id   blocking_instance,
			b.sid 		blocking_session,
			b.ctime 	sec_held,
			w.inst_id 	blocked_instance,
			w.sid 		blocked_session,
			w.ctime 	sec_wait
		FROM   
			gv$lock b, gv$lock w
		WHERE  
			b.request = 0
		AND w.lmode   = 0
		AND b.id1 = w.id1
		AND b.id2 = w.id2
    });
  
    if ( $params{mode} =~ /my::session::blocked/) {
	  if ( @blocked_sessionresult ) {
        foreach (@blocked_sessionresult) {
          my ($blocking_instance, $blocking_session, $sec_held, $blocked_instance, $blocked_session, $sec_wait) = @{$_};
  
		  my %thisparams = %params;
          $thisparams{blocking_instance} = $blocking_instance;
          $thisparams{blocking_session} = $blocking_session;
          $thisparams{sec_held} = $sec_held;
          $thisparams{blocked_instance} = $blocked_instance;
          $thisparams{blocked_session} = $blocked_session;
          $thisparams{sec_wait} = $sec_wait;
		              
          my $session = MySession::blocked->new(
              %thisparams);
          add_blocked_session($session);
          $num_blocked_sessions++;
        } # end foreach blocked_sessionsresult
	  } # end if blocked_sessionresult set
    } # end mode usage 
  }
}

sub new {
  my $class = shift;
  my %params = @_;
  my $self = {
    verbose => $params{verbose},
    handle => $params{handle},
    blocking_instance => $params{blocking_instance},
    blocking_session => $params{blocking_session},
    sec_held => $params{sec_held},
    blocked_instance => $params{blocked_instance},
    blocked_session => $params{blocked_session},
    sec_wait => $params{sec_wait},
    warningrange => $params{warningrange},
    criticalrange => $params{criticalrange},
  };
  bless $self, $class;
  $self->init(%params);
  return $self;
}

sub init {
  my $self = shift;
  my %params = @_;
  $self->init_nagios();
  $self->set_local_db_thresholds(%params);
}

sub nagios {
  my $self = shift;
  my %params = @_;
  if (! $self->{nagios_level}) {
    if ($params{mode} =~ /my::session::blocked/) {
      if ( $self->{blocking_session} ) {
	    $self->add_nagios(2,
                sprintf("session %d (instance: %d, age %ds) is blocking session %d (instance: %d, waiting: %ds)", 
				$self->{blocking_session}, $self->{blocking_instance}, $self->{sec_held}, 
				$self->{blocked_session}, $self->{blocked_instance}, $self->{sec_wait})
        );
      } # end if blocking_session
    } # end if mode
  } # end nagios level
} # end sub nagios

package MySession;

use strict;

our @ISA = qw(DBD::Oracle::Server);

sub new {
  my $class = shift;
  my %params = @_;
  my $self = {
    handle => $params{handle},
    warningrange => $params{warningrange},
    criticalrange => $params{criticalrange},
    blocked_sessions => [],
  };
  bless $self, $class;
  $self->init(%params);
  return $self;
}

sub init {
  my $self = shift;
  my %params = @_;
  $self->init_nagios();
  if ($params{mode} =~ /my::session::blocked/) {
    MySession::blocked::init_blocked_sessions(%params);
    if (my @blocked_sessions =
        MySession::blocked::return_blocked_sessions()) {
      $self->{blocked_sessions} = \@blocked_sessions;
    } else {
      $self->add_nagios_ok("no blocking session");
    }
  }
}

sub nagios {
  my $self = shift;
  my %params = @_;
  if (! $self->{nagios_level}) {
    if ($params{mode} =~ /my::session::blocked/) {
      foreach (@{$self->{blocked_sessions}}) {
        $_->nagios(%params);
        $self->merge_nagios($_);
      }
    }
  } 
}

