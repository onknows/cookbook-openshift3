#
# Cookbook Name:: cookbook-openshift3
# Recipe:: adhoc_migrate_etcd
#
# Copyright (c) 2015 The Authors, All Rights Reserved.

node.force_override['cookbook-openshift3']['upgrade'] = true
node.force_override['cookbook-openshift3']['ose_major_version'] = '3.6'
node.force_override['cookbook-openshift3']['ose_version'] = '3.6.1-1.0.008f2d5'

hosted_upgrade_version = node['cookbook-openshift3']['deploy_containerized'] == true ? node['cookbook-openshift3']['openshift_docker_image_version'] : 'v' + node['cookbook-openshift3']['ose_version'].to_s.split('-')[0]

server_info = OpenShiftHelper::NodeHelper.new(node)
etcd_servers = server_info.etcd_servers
is_certificate_server = server_info.on_certificate_server?
is_etcd_server = server_info.on_etcd_server?
is_master_server = server_info.on_master_server?
is_first_master = server_info.on_first_master?
is_first_etcd = server_info.on_first_etcd?

if is_first_etcd
  log 'Check if there is at least one v2 snapshot [Abort if not found]' do
    level :info
  end

  return unless ::Dir["#{node['cookbook-openshift3']['etcd_data_dir']}/member/snap/*.snap}"].any?
end

if is_master_server
  log 'Stop services on MASTERS [STARTED]' do
    level :info
  end

  notifies :stop, "service[#{node['cookbook-openshift3']['openshift_service_type']}-master]", :immediately unless node['cookbook-openshift3']['openshift_HA']
  notifies :stop, "service[#{node['cookbook-openshift3']['openshift_service_type']}-master-api]", :immediately if node['cookbook-openshift3']['openshift_HA']
  notifies :stop, "service[#{node['cookbook-openshift3']['openshift_service_type']}-master-controllers]", :immediately if node['cookbook-openshift3']['openshift_HA']
end
