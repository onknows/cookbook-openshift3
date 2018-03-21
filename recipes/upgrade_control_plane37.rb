#
# Cookbook Name:: cookbook-openshift3
# Recipe:: upgrade_control_plane37
#
# Copyright (c) 2015 The Authors, All Rights Reserved.

# This must be run before any upgrade takes place.
# It creates the service signer certs (and any others) if they were not in
# existence previously.

Chef::Log.error("Upgrade will be skipped. Could not find the flag: #{node['cookbook-openshift3']['control_upgrade_flag']}") unless ::File.file?(node['cookbook-openshift3']['control_upgrade_flag'])

if ::File.file?(node['cookbook-openshift3']['control_upgrade_flag'])

  node.force_override['cookbook-openshift3']['upgrade'] = true
  node.force_override['cookbook-openshift3']['ose_major_version'] = node['cookbook-openshift3']['upgrade_ose_major_version']
  node.force_override['cookbook-openshift3']['ose_version'] = node['cookbook-openshift3']['upgrade_ose_version']
  node.force_override['cookbook-openshift3']['openshift_docker_image_version'] = node['cookbook-openshift3']['upgrade_openshift_docker_image_version']

  server_info = OpenShiftHelper::NodeHelper.new(node)
  first_etcd = server_info.first_etcd
  is_master_server = server_info.on_master_server?

  if is_master_server
    return unless ::Mixlib::ShellOut.new("/usr/bin/etcdctl --cert-file #{node['cookbook-openshift3']['openshift_master_config_dir']}/master.etcd-client.crt --key-file #{node['cookbook-openshift3']['openshift_master_config_dir']}/master.etcd-client.key --ca-file #{node['cookbook-openshift3']['openshift_master_config_dir']}/master.etcd-ca.crt -C https://#{first_etcd['ipaddress']}:2379 ls /migration/#{node['cookbook-openshift3']['control_upgrade_version']}/#{node['fqdn']}").run_command.error?

    config_options = YAML.load_file("#{node['cookbook-openshift3']['openshift_common_master_dir']}/master/master-config.yaml")
    unless config_options['kubernetesMasterConfig']['apiServerArguments'].key?('storage-backend')
      Chef::Log.error('The cluster must be migrated to etcd v3 prior to upgrading to 3.7')
      node.run_state['issues_detected'] = true
    end
  end

  include_recipe 'cookbook-openshift3::upgrade_control_plane37_part1' unless node.run_state['issues_detected']
end
