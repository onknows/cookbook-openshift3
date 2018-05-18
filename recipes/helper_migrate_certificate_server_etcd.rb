#
# Cookbook Name:: is_apaas_openshift_cookbook
# Recipe:: helper_migrate_certificate_server_etcd
#
# Copyright (c) 2015 The Authors, All Rights Reserved.

helper = OpenShiftHelper::NodeHelper.new(node)

directory node['is_apaas_openshift_cookbook']['etcd_certs_generated_certs_dir'] do
  mode '0755'
  owner 'root'
  group 'root'
  recursive true
end

ruby_block 'Duplicate ETCD CA directory' do
  block do
    helper.backup_dir("#{node['is_apaas_openshift_cookbook']['legacy_etcd_ca_dir']}/.", node['is_apaas_openshift_cookbook']['etcd_certs_generated_certs_dir'])
  end
end
