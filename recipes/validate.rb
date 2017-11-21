#
# Cookbook Name:: cookbook-openshift3
# Recipe:: validate
#
# Copyright (c) 2015 The Authors, All Rights Reserved.

etcd_servers = if !node['cookbook-openshift3']['openshift_cluster_duty_discovery_id'].nil? && node.run_list.roles.include?("#{node['cookbook-openshift3']['openshift_cluster_duty_discovery_id']}_use_role_based_duty_discovery")
                 search(:node, "role:#{node['cookbook-openshift3']['openshift_cluster_duty_discovery_id']}_openshift_etcd_duty")
               else
                 node['cookbook-openshift3']['etcd_servers']
               end

if node['cookbook-openshift3']['ose_version']
  if node['cookbook-openshift3']['ose_version'].to_f.round(1) != node['cookbook-openshift3']['ose_major_version'].to_f.round(1)
    Chef::Application.fatal!("\"ose_version\" #{node['cookbook-openshift3']['ose_version']} should be a subset of \"ose_major_version\" #{node['cookbook-openshift3']['ose_major_version']}")
  end
end

if node['cookbook-openshift3']['use_wildcard_nodes'] && node['cookbook-openshift3']['wildcard_domain'].empty?
  Chef::Application.fatal!('"wildcard_domain" cannot be left empty when using "use_wildcard_nodes attribute"')
end

if node['cookbook-openshift3']['openshift_HA'] && node['cookbook-openshift3']['openshift_cluster_name'].nil?
  Chef::Application.fatal!('A Cluster Name must be defined via "openshift_cluster_name"')
end

if !node['cookbook-openshift3']['openshift_HA'] && node['cookbook-openshift3']['certificate_server'] != {}
  Chef::Application.fatal!('Separate certificate server and master standalone not supported.')
end

if node['cookbook-openshift3']['openshift_hosted_cluster_metrics']
  unless node['cookbook-openshift3']['openshift_metrics_cassandra_storage_types'].any? { |t| t.casecmp(node['cookbook-openshift3']['openshift_metrics_cassandra_storage_type']) == 0 }
    Chef::Application.fatal!('Key openshift_metrics_cassandra_storage_types is not valid. Please refer to the documentation for supprted types')
  end
end

if node['cookbook-openshift3']['etcd_add_additional_nodes']
  unless node['cookbook-openshift3']['etcd_add_additional_nodes'] && etcd_servers.any? { |key| key['new_node'] }
    Chef::Application.fatal!('A key named "new_node" must be defined when adding new members to ETCD cluster')
  end
end

%w(openshift_node_max_pod openshift_node_minimum_container_ttl_duration openshift_node_maximum_dead_containers_per_container openshift_node_maximum_dead_containers openshift_node_image_gc_high_threshold openshift_node_image_gc_low_threshold).each do |deprecated|
  unless node['cookbook-openshift3'][deprecated].empty?
    Chef::Log.warn("The attributes #{deprecated} has been deprecated, please use \"openshift_node_kubelet_args_custom\",")
  end
end

if !node['cookbook-openshift3']['openshift_cluster_duty_discovery_id'].nil? && node.run_list.roles.include?("#{node['cookbook-openshift3']['openshift_cluster_duty_discovery_id']}_use_role_based_duty_discovery")
  master_servers = search(:node, "role:#{node['cookbook-openshift3']['openshift_cluster_duty_discovery_id']}_openshift_master_duty")
  lb_servers = search(:node, "role:#{node['cookbook-openshift3']['openshift_cluster_duty_discovery_id']}_openshift_lb_duty")
  etcd_servers = search(:node, "role:#{node['cookbook-openshift3']['openshift_cluster_duty_discovery_id']}_openshift_etcd_duty")
  first_master = search(:node, "role:#{node['cookbook-openshift3']['openshift_cluster_duty_discovery_id']}_openshift_first_master_duty")[0]
  certificate_server = search(:node, "role:#{node['cookbook-openshift3']['openshift_cluster_duty_discovery_id']}_openshift_certificate_server_duty")[0]
  certificate_server = certificate_server.nil? ? first_master : certificate_server
else
  master_servers = node['cookbook-openshift3']['master_servers']
  lb_servers = node['cookbook-openshift3']['lb_servers']
  etcd_servers = node['cookbook-openshift3']['etcd_servers']
  first_master = master_servers.first
  certificate_server = node['cookbook-openshift3']['certificate_server'] == {} ? first_master : node['cookbook-openshift3']['certificate_server']
end

unless master_servers.is_a?(Array)
  Chef::Application.fatal!('master_servers not an array')
end
unless lb_servers.is_a?(Array)
  Chef::Application.fatal!('lb_servers not an array')
end
unless etcd_servers.is_a?(Array)
  Chef::Application.fatal!('etcd_servers not an array')
end
Chef::Application.fatal!('first_master not set') if first_master.nil?
if certificate_server.nil?
  Chef::Application.fatal!('certificate_server not set')
end
Chef::Application.fatal!('No master_servers set') if master_servers.empty?
