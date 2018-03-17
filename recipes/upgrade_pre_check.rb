#
# Cookbook Name:: cookbook-openshift3
# Recipe:: upgrade_pre_check
#
# Copyright (c) 2015 The Authors, All Rights Reserved.

server_info = OpenShiftHelper::NodeHelper.new(node)
first_etcd = server_info.first_etcd

# We do not want to run the upgrade again if it has already been run
# Avoiding potential rolebinding synchronisations etc...

execute 'test' do
  command "/usr/bin/etcdctl --cert-file #{node['cookbook-openshift3']['openshift_master_config_dir']}/master.etcd-client.crt --key-file #{node['cookbook-openshift3']['openshift_master_config_dir']}/master.etcd-client.key --ca-file #{node['cookbook-openshift3']['openshift_master_config_dir']}/master.etcd-ca.crt -C https://#{first_etcd['ipaddress']}:2379 ls /migration/#{node['cookbook-openshift3']['control_upgrade_version']}/#{node['fqdn']}"
end

warn 'Not enough minerals!' do
  return
end
