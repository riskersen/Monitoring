use Data::Dumper;

package MyAsm::Diskgroup;

use strict;

our @ISA = qw(MyAsm);

{
  my @diskgroups = ();
  my $initerrors = undef;
 
  sub add_diskgroup {
    push(@diskgroups, shift);
  }
  
  sub return_diskgroups {
    return @diskgroups;
    	#sort { $a->{name} cmp $b->{name} } @diskgroups;
  }
  
  sub init_diskgroups {
    my %params = @_;
    my $num_diskgroups = 0;
  
    my @diskgroupresult = ();
    @diskgroupresult = $params{handle}->fetchall_array(q{
          SELECT
                  name,
                  state,
                  type,
                  total_mb,
                  usable_file_mb,
                  offline_disks
          FROM
                  V$ASM_DISKGROUP
  
    });
  
    if (($params{mode} =~
        /my::asm::diskgroup::usage/) ||
        ($params{mode} =~ /my::asm::diskgroup::list/)) {
        foreach (@diskgroupresult) {
          my ($name, $state, $type, $total_mb, $usable_file_mb, $offline_disks) = @{$_};
          if ($params{regexp}) {
            next if $params{selectname} && $name !~ /$params{selectname}/;
          } else {
            next if $params{selectname} && lc $params{selectname} ne lc $name;
          }
  
  	  my %thisparams = %params;
          $thisparams{name} = $name;
          $thisparams{state} = lc $state;
          $thisparams{type} = lc $type;
          $thisparams{total_mb} = $total_mb;
          $thisparams{usable_file_mb} = $usable_file_mb;
          $thisparams{offline_disks} = $offline_disks;
  
          my $diskgroup = MyAsm::Diskgroup->new(
              %thisparams);
          add_diskgroup($diskgroup);
          $num_diskgroups++;
        }
        if (! $num_diskgroups) {
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
    state => $params{state},
    type => $params{type},
    total_mb => $params{total_mb},
    usable_file_mb => $params{usable_file_mb},
    offline_disks => $params{offline_disks},
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
  if ($params{mode} =~ /my::asm::diskgroup::usage/) {
    $self->{percent_used} =
	($self->{total_mb} - $self->{usable_file_mb}) / $self->{total_mb} * 100;
    $self->{percent_free} = 100 - $self->{percent_used};

    my $tlen = 20;
    my $len = int((($params{mode} =~ /my::asm::diskgroup::usage/) ?
        $self->{percent_used} : $self->{percent_free} / 100 * $tlen) + 0.5);
    $self->{percent_as_bar} = '=' x $len . '_' x ($tlen - $len);

  }
}

sub nagios {
  my $self = shift;
  my %params = @_;
  if (! $self->{nagios_level}) {
    if ($params{mode} =~ /my::asm::diskgroup::usage/) {
       ## if offline disk is greater 0 and is redundancy is external then critical
       # TODO: add check for voting disk
       if ( ($self->{offline_disks} > 0 && $self->{type} eq 'extern' ) ||
            ($self->{offline_disks} > 1 && $self->{type} eq 'high' ) ) { 
            
	    $self->add_nagios(
              defined $params{mitigation} ? $params{mitigation} : 2,
                sprintf("dg %s has %s offline disks", $self->{name}, $self->{offline_disks})
            );
       } elsif ($self->{offline_disks} > 0 && ( $self->{type} eq 'normal' || $self->{type} eq 'high') ) {
            $self->add_nagios(
              defined $params{mitigation} ? $params{mitigation} : 1,
                sprintf("dg %s has %s offline disks", $self->{name}, $self->{offline_disks})
            );
       }

       if ($self->{state} eq 'mounted' || $self->{state} eq 'connected') {
         # 'dg_system_usage_pct'=99.01%;90;98 percent used, warn, crit
         # 'dg_system_usage'=693MB;630;686;0;700 used, warn, crit, 0, max=total
         $self->add_nagios(
            $self->check_thresholds($self->{percent_used}, "90", "98"),
            $params{eyecandy} ?
                sprintf("[%s] %s", $self->{percent_as_bar}, $self->{name}) :
                sprintf("dg %s usage is %.2f%%",
                    $self->{name}, $self->{percent_used})
         );

         $self->add_perfdata(sprintf "\'dg_%s_usage_pct\'=%.2f%%;%d;%d",
            lc $self->{name},
            $self->{percent_used},
            $self->{warningrange}, $self->{criticalrange});
         $self->add_perfdata(sprintf "\'dg_%s_usage\'=%dMB;%d;%d;%d;%d",
             lc $self->{name},
             $self->{usable_file_mb},
             $self->{warningrange} * $self->{total_mb} / 100,
             $self->{criticalrange} * $self->{total_mb} / 100,
             0, $self->{total_mb});
       } else {
         $self->add_nagios(
           defined $params{mitigation} ? $params{mitigation} : 2,
             sprintf("dg %s has a problem, state is %s", $self->{name}, $self->{state})
         );
       }
    } 
  }
}

package MyAsm;

use strict;

our @ISA = qw(DBD::Oracle::Server);

sub new {
  my $class = shift;
  my %params = @_;
  my $self = {
    handle => $params{handle},
    warningrange => $params{warningrange},
    criticalrange => $params{criticalrange},
    diskgroups => [],
  };
  bless $self, $class;
  $self->init(%params);
  return $self;
}

sub init {
  my $self = shift;
  my %params = @_;
  $self->init_nagios();
  if ($params{mode} =~ /my::asm::diskgroup/) {
    MyAsm::Diskgroup::init_diskgroups(%params);
    if (my @diskgroups =
        MyAsm::Diskgroup::return_diskgroups()) {
      $self->{diskgroups} = \@diskgroups;
    } else {
      $self->add_nagios_critical("unable to aquire diskgroup info");
    }
  }
}

sub nagios {
  my $self = shift;
  my %params = @_;
  if (! $self->{nagios_level}) {
    if ($params{mode} =~ /my::asm::diskgroup::list/) {
	my $list = "Available DG: ";
      foreach ( sort { $a->{name} cmp $b->{name} }  @{$self->{diskgroups}} ) {
        $list .= $_->{name} . ", ";
      }
      $self->add_nagios_ok($list);
    } elsif ($params{mode} =~ /my::asm::diskgroup/) {
      foreach (@{$self->{diskgroups}}) {
        $_->nagios(%params);
        $self->merge_nagios($_);
      }
    }
  } 
}

