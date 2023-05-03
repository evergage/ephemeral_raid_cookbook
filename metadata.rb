name             'ephemeral_raid'
maintainer       'Alex Trull'
maintainer_email 'cookbooks.alex@trull.org'
license          'Apache 2.0'
description      'Creates Dynamic Ephemeral Raids on EC2 or GCE'
long_description IO.read(File.join(File.dirname(__FILE__), 'README.md'))
version          '0.0.12'

%w{ ubuntu debian redhat fedora centos scientific amazon }.each do |os|
  supports os
end
