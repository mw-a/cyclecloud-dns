name 'dns'
maintainer 's+c'
maintainer_email 'support@cyclecomputing.com'
license 'MIT'
description 'Configures DNS resolver'
long_description 'Configures DNS resolver'
version '1.0.0'
chef_version '>= 12.1' if respond_to?(:chef_version)

%w{ cvolume }.each {|c| depends c}
