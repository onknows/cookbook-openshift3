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

if defined? node['cookbook-openshift3']['upgrade_repos']
  node.force_override['cookbook-openshift3']['yum_repositories'] = node['cookbook-openshift3']['upgrade_repos']
end

include_recipe 'yum::default'
include_recipe 'cookbook-openshift3::packages'
include_recipe 'cookbook-openshift3::disable_excluder'

if is_etcd_server
  log 'Upgrade for ETCD [STARTED]' do
    level :info
  end

  include_recipe 'cookbook-openshift3::adhoc_backup_etcd'

  log 'Upgrade for ETCD [COMPLETED]' do
    level :info
  end

  file node['cookbook-openshift3']['control_upgrade_flag'] do
    action :delete
    only_if { is_etcd_server && !is_master_server }
  end
end

include_recipe 'cookbook-openshift3::upgrade_control_plane37_part2'
