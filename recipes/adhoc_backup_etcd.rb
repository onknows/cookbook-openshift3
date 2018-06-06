#
# Cookbook Name:: cookbook-openshift3
# Recipe:: adhoc_backup_etcd
#
# Copyright (c) 2015 The Authors, All Rights Reserved.

# This must be run before any upgrade takes place.
# It creates the service signer certs (and any others) if they were not in
# existence previously.

server_info = OpenShiftHelper::NodeHelper.new(node)
is_etcd_server = server_info.on_etcd_server?

backup_suffix = 'adhoc_backup_' + Time.now.strftime('%s')
if node['cookbook-openshift3']['control_upgrade']
  backup_suffix = "upgrade#{node['cookbook-openshift3']['control_upgrade_version']}"
end

if is_etcd_server

  execute 'Generate etcd backup before upgrade' do
    command "etcdctl backup --data-dir=#{node['cookbook-openshift3']['etcd_data_dir']} --backup-dir=#{node['cookbook-openshift3']['etcd_data_dir']}-pre-#{backup_suffix}"
    not_if { ::File.directory?("#{node['cookbook-openshift3']['etcd_data_dir']}-pre-#{backup_suffix}") }
    notifies :run, 'execute[Copy etcd v3 data store (PRE)]', :immediately
  end

  execute 'Copy etcd v3 data store (PRE)' do
    command "cp -a #{node['cookbook-openshift3']['etcd_data_dir']}/member/snap/db #{node['cookbook-openshift3']['etcd_data_dir']}-pre-#{backup_suffix}/member/snap/"
    only_if { ::File.file?("#{node['cookbook-openshift3']['etcd_data_dir']}/member/snap/db") }
    action :nothing
  end

  include_recipe 'cookbook-openshift3'
  include_recipe 'cookbook-openshift3::etcd_cluster'

  execute 'Generate etcd backup after upgrade' do
    command "etcdctl backup --data-dir=#{node['cookbook-openshift3']['etcd_data_dir']} --backup-dir=#{node['cookbook-openshift3']['etcd_data_dir']}-post-#{backup_suffix}"
    not_if { ::File.directory?("#{node['cookbook-openshift3']['etcd_data_dir']}-post-#{backup_suffix}") }
    notifies :run, 'execute[Copy etcd v3 data store (POST)]', :immediately
  end

  execute 'Copy etcd v3 data store (POST)' do
    command "cp -a #{node['cookbook-openshift3']['etcd_data_dir']}/member/snap/db #{node['cookbook-openshift3']['etcd_data_dir']}-post-#{backup_suffix}/member/snap/"
    only_if { ::File.file?("#{node['cookbook-openshift3']['etcd_data_dir']}/member/snap/db") }
    action :nothing
  end

end
