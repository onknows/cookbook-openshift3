#
# Cookbook Name:: cookbook-openshift3
# Recipe:: upgrade_control_plane37_part1
#
# Copyright (c) 2015 The Authors, All Rights Reserved.

# This must be run before any upgrade takes place.
# It creates the service signer certs (and any others) if they were not in
# existence previously.

server_info = OpenShiftHelper::NodeHelper.new(node)
is_etcd_server = server_info.on_etcd_server?
is_master_server = server_info.on_master_server?
is_node_server = server_info.on_node_server?

if defined? node['cookbook-openshift3']['upgrade_repos']
  node.force_override['cookbook-openshift3']['yum_repositories'] = node['cookbook-openshift3']['upgrade_repos']
end

include_recipe 'yum::default'
include_recipe 'cookbook-openshift3::packages'

if is_master_server || is_node_server
  %w(excluder docker-excluder).each do |pkg|
    execute "Disable #{node['cookbook-openshift3']['openshift_service_type']}-#{pkg}" do
      command "#{node['cookbook-openshift3']['openshift_service_type']}-#{pkg} enable"
    end
  end
end

if is_etcd_server
  log 'Upgrade for ETCD [STARTED]' do
    level :info
  end

  execute 'Generate etcd backup before upgrade' do
    command "etcdctl backup --data-dir=#{node['cookbook-openshift3']['etcd_data_dir']} --backup-dir=#{node['cookbook-openshift3']['etcd_data_dir']}-pre-upgrade37"
    not_if { ::File.directory?("#{node['cookbook-openshift3']['etcd_data_dir']}-pre-upgrade37") }
    notifies :run, 'execute[Copy etcd v3 data store (PRE)]', :immediately
  end

  execute 'Copy etcd v3 data store (PRE)' do
    command "cp -a #{node['cookbook-openshift3']['etcd_data_dir']}/member/snap/db #{node['cookbook-openshift3']['etcd_data_dir']}-pre-upgrade37/member/snap/"
    only_if { ::File.file?("#{node['cookbook-openshift3']['etcd_data_dir']}/member/snap/db") }
    action :nothing
  end

  include_recipe 'cookbook-openshift3'
  include_recipe 'cookbook-openshift3::etcd_cluster'

  execute 'Generate etcd backup after upgrade' do
    command "etcdctl backup --data-dir=#{node['cookbook-openshift3']['etcd_data_dir']} --backup-dir=#{node['cookbook-openshift3']['etcd_data_dir']}-post-upgrade37"
    not_if { ::File.directory?("#{node['cookbook-openshift3']['etcd_data_dir']}-post-upgrade37") }
    notifies :run, 'execute[Copy etcd v3 data store (POST)]', :immediately
  end

  execute 'Copy etcd v3 data store (POST)' do
    command "cp -a #{node['cookbook-openshift3']['etcd_data_dir']}/member/snap/db #{node['cookbook-openshift3']['etcd_data_dir']}-post-upgrade37/member/snap/"
    only_if { ::File.file?("#{node['cookbook-openshift3']['etcd_data_dir']}/member/snap/db") }
    action :nothing
  end

  log 'Upgrade for ETCD [COMPLETED]' do
    level :info
  end

  file node['cookbook-openshift3']['control_upgrade_flag'] do
    action :delete
    only_if { is_etcd_server && !is_master_server }
  end
end

include_recipe 'cookbook-openshift3::upgrade_control_plane37_part2'
