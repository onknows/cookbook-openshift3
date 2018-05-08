#
# Cookbook Name:: cookbook-openshift3
# Recipe:: adhoc_redeploy_certificates
#
# Copyright (c) 2015 The Authors, All Rights Reserved.

server_info = OpenShiftHelper::NodeHelper.new(node)
is_certificate_server = server_info.on_certificate_server?
is_first_master = server_info.on_first_master?

include_recipe 'cookbook-openshift3::services'

if is_certificate_server
  include_recipe 'cookbook-openshift3::adhoc_redeploy_etcd_ca' if node['cookbook-openshift3']['adhoc_redeploy_etcd_ca']
  include_recipe 'cookbook-openshift3::adhoc_redeploy_cluster_ca' if node['cookbook-openshift3']['adhoc_redeploy_cluster_ca']
end

if is_first_master
  include_recipe 'cookbook-openshift3::adhoc_redeploy_cluster_hosted' if node['cookbook-openshift3']['adhoc_redeploy_cluster_ca']
end
