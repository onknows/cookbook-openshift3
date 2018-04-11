#
# Cookbook Name:: cookbook-openshift3
# Recipe:: adhoc_migrate_certificate_server
#
# Copyright (c) 2015 The Authors, All Rights Reserved.

directory node['cookbook-openshift3']['master_certs_generated_certs_dir'] do
  mode '0755'
  owner 'apache'
  group 'apache'
  recursive true
end

Dir.glob('/etc/origin/master/*').grep(/\.(?:crt|key|kubeconfig|txt)$/).uniq.each do |master_certificate|
  remote_file "#{node['cookbook-openshift3']['master_certs_generated_certs_dir']}/#{::File.basename(master_certificate)}" do
    source "file://#{master_certificate}"
    sensitive true
  end
end
