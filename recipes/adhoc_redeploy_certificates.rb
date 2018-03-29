#
# Cookbook Name:: is_apaas_openshift_cookbook
# Recipe:: adhoc_redeploy_certificates
#
# Copyright (c) 2015 The Authors, All Rights Reserved.

server_info = OpenShiftHelper::NodeHelper.new(node)

include_recipe 'is_apaas_openshift_cookbook::services'

if server_info.on_control_plane_server?
  include_recipe 'is_apaas_openshift_cookbook::adhoc_redeploy_etcd_ca' if node['is_apaas_openshift_cookbook']['adhoc_redeploy_etcd_ca']
  include_recipe 'is_apaas_openshift_cookbook::adhoc_redeploy_etcd_certs' if node['is_apaas_openshift_cookbook']['adhoc_redeploy_etcd_certs']
end
