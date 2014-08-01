use Data::Dumper;

package MyEvent::wait;

use strict;

our @ISA = qw(MyEvent);

{
  my @eventswait = ();
  my $initerrors = undef;
 
  sub add_eventwait {
    push(@eventswait, shift);
  }
  
  sub return_eventwaits {
    return @eventswait;
  }
  
  sub init_eventwaits {
    my %params = @_;
    my $num_eventwaits = 0;
  
    my @eventwaitresult = ();
	# fetch wait time in seconds, thus / 1.000.000
    @eventwaitresult = $params{handle}->fetchall_array(q{
		SELECT
			wait_class name, 
			ROUND(SUM(time_waited_micro)/1000000) time_waited
		FROM
			v$system_event
		WHERE 
			wait_class <> 'Idle'
		GROUP BY
			wait_class
		UNION ALL
			SELECT 
				'CPU', 
				ROUND(SUM(value)/1000000)
			FROM
				v$sys_time_model
			WHERE
				STAT_NAME in ('background cpu time', 'DB CPU')
    });
    if ($params{mode} =~ /my::event::wait/) {
        foreach (@eventwaitresult) {
          my ($name, $time_waited) = @{$_};
  
		  my %thisparams = %params;
          $thisparams{name} = $name;
          $thisparams{time_waited} = $time_waited;
		              
          my $eventwait = MyEvent::wait->new(
              %thisparams);
          add_eventwait($eventwait);
          $num_eventwaits++;
        }
		if (! $num_eventwaits) {
          $initerrors = 1;
          return undef;
        }
    } # end mode usage 
  }
}

sub new {
  my $class = shift;
  my %params = @_;
  my $self = {
    verbose => $params{verbose},
    handle => $params{handle},
    name => $params{name},
    time_waited => $params{time_waited},
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
  
  if ($params{mode} =~ /my::event::wait/) {
    $self->valdiff(\%params, qw(time_waited));
	$self->{time_waited_rate} = $self->{delta_time_waited} ? 
										$self->{delta_time_waited} / ($self->{delta_timestamp}/1000) : 0;
	$self->{time_waited_percent} = $self->{time_waited_rate} ? 
									($self->{time_waited_rate}) / $self->{time_waited} * 100 : 0;
  }
}

sub nagios {
  my $self = shift;
  my %params = @_;
  if (! $self->{nagios_level}) {
    if ($params{mode} =~ /my::event::wait/) {
        $self->add_nagios(
          $self->check_thresholds($self->{time_waited_percent}, "40", "60"),
              $self->{time_waited_percent} ? 
			     sprintf("%s raised to %.2f%% (%.2f/s)",
                   $self->{name}, $self->{time_waited_percent}, $self->{time_waited_rate}) :
			     sprintf("%s: %.2f%% (%.2f/ms)",
                   $self->{name}, $self->{time_waited_percent}, $self->{time_waited_rate})
		);

      $self->add_perfdata(sprintf "\'%s_wait_rate_pct\'=%.2f%%;%.2f;%.2f",
        lc $self->{name},
        $self->{time_waited_percent},
        $self->{warningrange}, $self->{criticalrange});

      $self->add_perfdata(sprintf "\'%s_delta_wait\'=%.2fms;%.2f;%.2f;%.2f;%.2f",
        lc $self->{name},
        $self->{delta_time_waited},
        $self->{warningrange} * $self->{delta_time_waited} / 100,
        $self->{criticalrange} * $self->{delta_time_waited} / 100,
	    0, $self->{time_waited});
		
      $self->add_perfdata(sprintf "\'%s_wait_rate_per_sec\'=%.2f;%.2f;%.2f;%.2f;%.2f",
        lc $self->{name},
        $self->{time_waited_rate},
        $self->{warningrange} * $self->{time_waited_rate} / 100,
        $self->{criticalrange} * $self->{time_waited_rate} / 100,
	    0, $self->{time_waited});
    } 
  }
}

package MyEvent;

use strict;

our @ISA = qw(DBD::Oracle::Server);

sub new {
  my $class = shift;
  my %params = @_;
  my $self = {
    handle => $params{handle},
    warningrange => $params{warningrange},
    criticalrange => $params{criticalrange},
    eventwaits => [],
  };
  bless $self, $class;
  $self->init(%params);
  return $self;
}

sub init {
  my $self = shift;
  my %params = @_;
  $self->init_nagios();
  if ($params{mode} =~ /my::event::wait/) {
    MyEvent::wait::init_eventwaits(%params);
    if (my @eventwaits =
        MyEvent::wait::return_eventwaits()) {
      $self->{eventwaits} = \@eventwaits;
    } else {
      $self->add_nagios_critical("unable to aquire eventwait info");
    }
  }
}

sub nagios {
  my $self = shift;
  my %params = @_;
  if (! $self->{nagios_level}) {
    if ($params{mode} =~ /my::event::wait::list/) {
	my $list = "Available wait events: ";
      foreach ( sort { $a->{name} cmp $b->{name} }  @{$self->{eventwaits}} ) {
        $list .= $_->{name} . ", ";
      }
      $self->add_nagios_ok($list);
    } elsif ($params{mode} =~ /my::event::wait/) {
      foreach (@{$self->{eventwaits}}) {
        $_->nagios(%params);
        $self->merge_nagios($_);
      }
    }
  } 
}

