# == Class: samba
#
# Full description of class samba here.
#
# === Parameters
#
# Document parameters here.
#
# [*sample_parameter*]
#   Explanation of what this parameter affects and what it defaults to.
#   e.g. "Specify one or more upstream ntp servers as an array."
#
# === Variables
#
# Here you should define a list of variables that this module would require.
#
# [*sample_variable*]
#   Explanation of how this variable affects the funtion of this class and if
#   it has a default. e.g. "The parameter enc_ntp_servers must be set by the
#   External Node Classifier as a comma separated list of hostnames." (Note,
#   global variables should be avoided in favor of class parameters as
#   of Puppet 2.6.)
#
# === Examples
#
#  class { 'samba':
#    servers => [ 'pool.ntp.org', 'ntp.local.company.com' ],
#  }
#
# === Authors
#
# Pierre-Francois Carpentier <carpentier.pf@gmail.com>
#
# === Copyright
#
# Copyright 2015 Pierre-Francois Carpentier, unless otherwise noted.
#
class samba::classic(
  Optional[String[1,15]] $smbname = undef,
  Optional[Stdlib::Fqdn] $domain  = undef,
  Optional[Stdlib::Fqdn] $realm   = undef,
  $strictrealm                    = true,
  $adminuser                      = 'administrator',
  $adminpassword                  = undef,
  $security                       = 'ads',
  $sambaloglevel                  = 1,
  $join_domain                    = true,
  $manage_winbind                 = true,
  $krbconf                        = true,
  $nsswitch                       = true,
  $pam                            = false,
  $sambaclassloglevel             = undef,
  $logtosyslog                    = false,
  $globaloptions                  = {},
  $globalabsentoptions            = [],
  $joinou                         = undef,
  Optional[String] $default_realm = undef,
  Array $additional_realms        = [],
  $krbconffile                    = $samba::params::krbconffile,
  $nsswitchconffile               = $samba::params::nsswitchconffile,
  $smbconffile                    = $samba::params::smbconffile,
  $sambaoptsfile                  = $samba::params::sambaoptsfile,
  $sambaoptstmpl                  = $samba::params::sambaoptstmpl,
  $sambacreatehome                = $samba::params::sambacreatehome,
  $servicesmb                     = $samba::params::servicesmb,
  $servicewinbind                 = $samba::params::servicewinbind,
  $packagesambawinbind            = $samba::params::packagesambawinbind,
  $packagesambansswinbind         = $samba::params::packagesambansswinbind,
  $packagesambapamwinbind         = $samba::params::packagesambapamwinbind,
  $packagesambaclassic            = $samba::params::packagesambaclassic,
) inherits samba::params{

  if $strictrealm {
    $tmparr = split($realm, '[.]')
    unless $domain == $tmparr[0] {
      fail('domain must be the fist part of realm, ex: domain="ad" and realm="ad.example.com"')
    }
  }

  $checksecurity = ['ads', 'auto', 'user', 'domain']
  $checksecuritystr = join($checksecurity, ', ')

  unless member($checksecurity, downcase($security)){
    fail("role must be in [${checksecuritystr}]")
  }


  $realmlowercase = downcase($realm)
  $realmuppercase = upcase($realm)
  $globaloptsexclude = concat(keys($globaloptions), $globalabsentoptions)

  $_default_realm = pick($default_realm, $realmuppercase)


  file { '/etc/samba/':
    ensure  => 'directory',
  }

  file { '/etc/samba/smb_path':
    ensure  => 'present',
    content => $smbconffile,
    require => File['/etc/samba/'],
  }

  if $join_domain {
    if $krbconf {
      file {$krbconffile:
        ensure  => present,
        mode    => '0644',
        content => template("${module_name}/krb5.conf.erb"),
        notify  => Service['SambaSmb', 'SambaWinBind'],
      }
    }

    if $nsswitch {
      package{ 'SambaNssWinbind':
        ensure => 'installed',
        name   => $packagesambansswinbind
      }

      augeas{'samba nsswitch group':
        context => "/files/${nsswitchconffile}/",
        changes => [
          'ins service after "*[self::database = \'group\']/service[1]/"',
          'set "*[self::database = \'group\']/service[2]" winbind',
        ],
        onlyif  => 'get "*[self::database = \'group\']/service[2]" != winbind',
        lens    => 'Nsswitch.lns',
        incl    => $nsswitchconffile,
      }
      augeas{'samba nsswitch passwd':
        context => "/files/${nsswitchconffile}/",
        changes => [
          'ins service after "*[self::database = \'passwd\']/service[1]/"',
          'set "*[self::database = \'passwd\']/service[2]" winbind',
        ],
        onlyif  => 'get "*[self::database = \'passwd\']/service[2]" != winbind',
        lens    => 'Nsswitch.lns',
        incl    => $nsswitchconffile,
      }
    }

    if $pam {
      # Only add package here if different to the nss-winbind package,
      # or nss and pam aren't both enabled, to avoid duplicate definition.
      if ($packagesambapamwinbind != $packagesambansswinbind)
      or !$nsswitch {
        package{ 'SambaPamWinbind':
          ensure => 'installed',
          name   => $packagesambapamwinbind
        }
      }

      if $krbconf {
        $winbindauthargs = ['krb5_auth', 'krb5_ccache_type=FILE', 'cached_login', 'try_first_pass']
      } else {
        $winbindauthargs = ['cached_login', 'try_first_pass']
      }

      pam { 'samba pam winbind auth':
        ensure    => present,
        service   => 'system-auth',
        type      => 'auth',
        control   => 'sufficient',
        module    => 'pam_winbind.so',
        arguments => $winbindauthargs,
        position  => 'before module pam_deny.so'
      }

      pam { 'samba pam winbind account':
        ensure    => present,
        service   => 'system-account',
        type      => 'account',
        control   => 'required',
        module    => 'pam_winbind.so',
        arguments => 'use_first_pass',
        position  => 'before module pam_deny.so'
      }

      pam { 'samba pam winbind session':
        ensure   => present,
        service  => 'system-session',
        type     => 'session',
        control  => 'optional',
        module   => 'pam_winbind.so',
        position => 'after module pam_unix.so'
      }

      pam { 'samba pam winbind password':
        ensure    => present,
        service   => 'system-password',
        type      => 'password',
        control   => 'sufficient',
        module    => 'pam_winbind.so',
        arguments => ['use_authtok', 'try_first_pass'],
        position  => 'before module pam_deny.so'
      }
    }
  }

  package{ 'SambaClassic':
    ensure => 'installed',
    name   => $packagesambaclassic,
  }

  if $manage_winbind {
    package{ 'SambaClassicWinBind':
      ensure  => 'installed',
      name    => $packagesambawinbind,
      require => File['/etc/samba/smb_path'],
    }
    Package['SambaClassicWinBind'] -> Package['SambaClassic']
  }

  service{ 'SambaSmb':
    ensure  => 'running',
    name    => $servicesmb,
    require => [ Package['SambaClassic'], File['SambaOptsFile'] ],
    enable  => true,
  }

  if $manage_winbind {
    service{ 'SambaWinBind':
      ensure  => 'running',
      name    => $servicewinbind,
      require => [ Package['SambaClassic'], File['SambaOptsFile'], Exec['Join Domain'], ],
      enable  => true,
    }
  }
  $sambamode = 'classic'
  # Deploy /etc/sysconfig/|/etc/defaut/ file (startup options)
  file{ 'SambaOptsFile':
    path    => $sambaoptsfile,
    content => template($sambaoptstmpl),
    require => Package['SambaClassic'],
  }

  if $manage_winbind {
    $mandatoryglobaloptions = {
      'workgroup'                          => $domain,
      'realm'                              => $realm,
      'netbios name'                       => $smbname,
      'security'                           => $security,
      'dedicated keytab file'              => '/etc/krb5.keytab',
      'vfs objects'                        => 'acl_xattr',
      'map acl inherit'                    => 'Yes',
      'store dos attributes'               => 'Yes',
      'map untrusted to domain'            => 'Yes',
      'winbind nss info'                   => 'rfc2307',
      'winbind trusted domains only'       => 'No',
      'winbind use default domain'         => 'Yes',
      'winbind enum users'                 => 'Yes',
      'winbind enum groups'                => 'Yes',
      'winbind refresh tickets'            => 'Yes',
      'winbind separator'                  => '+',
    }
  }
  else {
    $mandatoryglobaloptions = {
      'workgroup'                          => $domain,
      'realm'                              => $realm,
      'netbios name'                       => $smbname,
      'security'                           => $security,
      'vfs objects'                        => 'acl_xattr',
      'dedicated keytab file'              => '/etc/krb5.keytab',
      'map acl inherit'                    => 'Yes',
      'store dos attributes'               => 'Yes',
      'map untrusted to domain'            => 'Yes',
    }
  }

  file{ 'SambaCreateHome':
    path   => $sambacreatehome,
    source => "puppet:///modules/${module_name}/smb-create-home.sh",
    mode   => '0755',
  }

  $mandatoryglobaloptionsindex = prefix(keys($mandatoryglobaloptions),
    '[global]')

  if $manage_winbind {
    $services_to_notify = ['SambaSmb', 'SambaWinBind']
  }
  else {
    $services_to_notify = ['SambaSmb']
  }
  samba::option{ $mandatoryglobaloptionsindex:
    options         => $mandatoryglobaloptions,
    section         => 'global',
    settingsignored => $globaloptsexclude,
    require         => Package['SambaClassic'],
    notify          => Service[$services_to_notify],
  }

  samba::log { 'syslog':
    sambaloglevel      => $sambaloglevel,
    logtosyslog        => $logtosyslog,
    sambaclassloglevel => $sambaclassloglevel,
    settingsignored    => $globaloptsexclude,
    require            => Package['SambaClassic'],
    notify             => Service[$services_to_notify],
  }

  # Iteration on global options
  $globaloptionsindex = prefix(keys($globaloptions), '[globalcustom]')
  samba::option{ $globaloptionsindex:
    options => $globaloptions,
    section => 'global',
    require => Package['SambaClassic'],
    notify  => Service[$services_to_notify],
  }

  resources { 'smb_setting':
    purge => true,
  }

  $gabsoptlist = prefix($globalabsentoptions, 'global/')
  smb_setting { $gabsoptlist :
    ensure  => absent,
    section => 'global',
    require => Package['SambaClassic'],
    notify  => Service[$services_to_notify],
  }

  if $manage_winbind and $join_domain {
    unless $adminpassword == undef {
      $command = $joinou ? {
        default => $::facts['os']['family'] ? {
          'RedHat' => "dnshostname=\"${::facts['fqdn']}\" createcomputer=\"${joinou}\"",
          default  => "createcomputer=\"${joinou}\"",
        },
        undef   => $::facts['os']['family'] ? {
          'RedHat' => "dnshostname=\"${::facts['fqdn']}\"",
          default  => '',
        },
      }

      exec{ 'Join Domain':
        path    => '/bin:/sbin:/usr/sbin:/usr/bin/',
        unless  => 'net ads testjoin',
        command => "echo '${adminpassword}'| net ads join -U '${adminuser}' ${command}",
        notify  => Service['SambaWinBind'],
        before  => Service['SambaSmb'],
        require => [ Package['SambaClassic'], ],
      }
    }
  }
}

# vim: tabstop=8 expandtab shiftwidth=2 softtabstop=2
