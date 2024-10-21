#!/usr/bin/ruby
require 'facter'

# package = 'samba'


distid = Facter.value(:operatingsystem)

case distid
    when /RedHatEnterprise|CentOS|Fedora|RHEL/
        if Facter::Util::Resolution.which('yum')
            version = Facter::Util::Resolution.exec('/usr/bin/yum info samba | sed \'s/Version *: \([0-9\.]\+\)/\1/gp;d\' | head -n 1')
        end
    when /Ubuntu|Debian/
        if Facter::Util::Resolution.which('apt-cache')
            version = Facter::Util::Resolution.exec('apt-cache show samba | sed \'s/Version:.*:\([0-9\.]\+\).*/\1/gp;d\' | head -n 1')
        end
    when 'Archlinux'
      version = Facter::Util::Resolution.exec('pacman -Si samba | awk "/Version/ {print $3}" | cut -d"-" -f1')
    else
        version = "0.0.0"
end

#print distid
#print version

Facter.add("samba_version") do
    setcode do
        version
    end
end

