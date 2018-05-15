#
# Cookbook Name:: cookbook-openshift3
# Recipe:: node
#
# Copyright (c) 2015 The Authors, All Rights Reserved.

server_info = helper = OpenShiftHelper::NodeHelper.new(node)
node_servers = server_info.node_servers
certificate_server = server_info.certificate_server
is_node_server = server_info.on_node_server?
first_master = server_info.first_master
docker_version = node['cookbook-openshift3']['openshift_docker_image_version']

ose_major_version = node['cookbook-openshift3']['deploy_containerized'] == true ? node['cookbook-openshift3']['openshift_docker_image_version'] : node['cookbook-openshift3']['ose_major_version']
path_certificate = node['cookbook-openshift3']['use_wildcard_nodes'] ? 'wildcard_nodes.tgz.enc' : "#{node['fqdn']}.tgz.enc"

if node['cookbook-openshift3']['encrypted_file_password']['data_bag_name'] && node['cookbook-openshift3']['encrypted_file_password']['data_bag_item_name']
  secret_file = node['cookbook-openshift3']['encrypted_file_password']['secret_file'] || nil
  encrypted_file_password = data_bag_item(node['cookbook-openshift3']['encrypted_file_password']['data_bag_name'], node['cookbook-openshift3']['encrypted_file_password']['data_bag_item_name'], secret_file)
else
  encrypted_file_password = node['cookbook-openshift3']['encrypted_file_password']['default']
end

if is_node_server
  ruby_block 'Turn off SWAP for nodes' do
    block do
      server_info.turn_off_swap
    end
    only_if { ::File.readlines('/etc/fstab').grep(/(^[^#].*swap.*)\n/).any? }
  end

  file '/usr/local/etc/.firewall_node_additional.txt' do
    content node['cookbook-openshift3']['enabled_firewall_additional_rules_node'].join("\n")
    owner 'root'
    group 'root'
  end

  node['cookbook-openshift3']['enabled_firewall_rules_node'].each do |rule|
    iptables_rule rule do
      action :enable
    end
  end

  directory node['cookbook-openshift3']['openshift_node_config_dir'] do
    recursive true
  end

  if node['cookbook-openshift3']['deploy_containerized']
    docker_image node['cookbook-openshift3']['openshift_docker_node_image'] do
      tag docker_version
      action :pull_if_missing
    end

    docker_image node['cookbook-openshift3']['openshift_docker_ovs_image'] do
      tag docker_version
      action :pull_if_missing
    end

    template "/etc/systemd/system/#{node['cookbook-openshift3']['openshift_service_type']}-node-dep.service" do
      source 'service_node-deps-containerized.service.erb'
      notifies :run, 'execute[daemon-reload]', :immediately
    end

    template "/etc/systemd/system/#{node['cookbook-openshift3']['openshift_service_type']}-node.service" do
      source 'service_node-containerized.service.erb'
      notifies :run, 'execute[daemon-reload]', :immediately
      variables(ose_major_version: ose_major_version)
    end

    template '/etc/systemd/system/openvswitch.service' do
      source 'service_openvswitch-containerized.service.erb'
      notifies :run, 'execute[daemon-reload]', :immediately
    end

    template '/etc/sysconfig/openvswitch' do
      source 'service_openvswitch.sysconfig.erb'
      notifies :restart, 'service[openvswitch]', :immediately unless node['cookbook-openshift3']['upgrade']
    end
  else
    template "/etc/systemd/system/#{node['cookbook-openshift3']['openshift_service_type']}-node.service" do
      source 'service_node.service.erb'
      notifies :run, 'execute[daemon-reload]', :immediately
      variables(ose_major_version: ose_major_version)
      only_if { ose_major_version.split('.')[1].to_i >= 6 }
    end
  end

  sysconfig_vars = {}

  if node['cookbook-openshift3']['openshift_cloud_provider'] == 'aws'
    if node['cookbook-openshift3']['openshift_cloud_providers']['aws']['data_bag_name'] && node['cookbook-openshift3']['openshift_cloud_providers']['aws']['data_bag_item_name']
      secret_file = node['cookbook-openshift3']['openshift_cloud_providers']['aws']['secret_file'] || nil
      aws_vars = data_bag_item(node['cookbook-openshift3']['openshift_cloud_providers']['aws']['data_bag_name'], node['cookbook-openshift3']['openshift_cloud_providers']['aws']['data_bag_item_name'], secret_file)

      sysconfig_vars['aws_access_key_id'] = aws_vars['access_key_id']
      sysconfig_vars['aws_secret_access_key'] = aws_vars['secret_access_key']
    end
  end

  template "/etc/sysconfig/#{node['cookbook-openshift3']['openshift_service_type']}-node" do
    source 'service_node.sysconfig.erb'
    variables(sysconfig_vars)
    notifies :restart, 'service[Restart Node]', :immediately unless node['cookbook-openshift3']['upgrade']
  end

  package "#{node['cookbook-openshift3']['openshift_service_type']}-node" do
    action :install
    version node['cookbook-openshift3']['ose_version'] unless node['cookbook-openshift3']['ose_version'].nil?
    options node['cookbook-openshift3']['yum_options'] unless node['cookbook-openshift3']['yum_options'].nil?
    not_if { node['cookbook-openshift3']['deploy_containerized'] }
    retries 3
  end

  package "#{node['cookbook-openshift3']['openshift_service_type']}-sdn-ovs" do
    action :install
    version node['cookbook-openshift3']['ose_version'] unless node['cookbook-openshift3']['ose_version'].nil?
    options node['cookbook-openshift3']['yum_options'] unless node['cookbook-openshift3']['yum_options'].nil?
    only_if { node['cookbook-openshift3']['openshift_common_use_openshift_sdn'] == true }
    not_if { node['cookbook-openshift3']['deploy_containerized'] }
    retries 3
  end

  package 'conntrack-tools' do
    action :install
    not_if { node['cookbook-openshift3']['deploy_containerized'] }
    retries 3
  end

  if node['cookbook-openshift3']['adhoc_redeploy_cluster_ca']
    Chef::Log.warn("The CLUSTER CA CERTS redeploy will be skipped for Node[#{node['fqdn']}]. Could not find the flag: #{node['cookbook-openshift3']['redeploy_cluster_ca_nodes_control_flag']}") unless ::File.file?(node['cookbook-openshift3']['redeploy_cluster_ca_nodes_control_flag'])

    ruby_block "Redeploy CA certs for #{node['fqdn']}" do
      block do
        helper.remove_dir("#{node['cookbook-openshift3']['openshift_node_config_dir']}/#{node['fqdn']}.tgz*")
      end
      only_if { ::File.file?(node['cookbook-openshift3']['redeploy_cluster_ca_nodes_control_flag']) }
      notifies :delete, "file[#{node['cookbook-openshift3']['redeploy_cluster_ca_nodes_control_flag']}]", :immediately
      notifies :restart, 'service[Restart Node]', :delayed if ::File.file?(node['cookbook-openshift3']['redeploy_cluster_ca_nodes_control_flag'])
    end

    file node['cookbook-openshift3']['redeploy_cluster_ca_nodes_control_flag'] do
      action :nothing
    end
  end

  remote_file "Retrieve certificate from Master[#{certificate_server['fqdn']}]" do
    path "#{node['cookbook-openshift3']['openshift_node_config_dir']}/#{node['fqdn']}.tgz.enc"
    source "http://#{certificate_server['ipaddress']}:#{node['cookbook-openshift3']['httpd_xfer_port']}/node/generated-configs/#{path_certificate}"
    action :create_if_missing
    notifies :run, 'execute[Un-encrypt node certificate tgz files]', :immediately
    notifies :run, 'execute[Extract certificate to Node folder]', :immediately
    retries 60
    retry_delay 5
  end

  execute 'Un-encrypt node certificate tgz files' do
    command "openssl enc -d -aes-256-cbc -in #{node['cookbook-openshift3']['openshift_node_config_dir']}/#{node['fqdn']}.tgz.enc -out #{node['cookbook-openshift3']['openshift_node_config_dir']}/#{node['fqdn']}.tgz -k '#{encrypted_file_password}'"
    action :nothing
  end

  execute 'Extract certificate to Node folder' do
    command "tar xzf #{node['fqdn']}.tgz && chown -R root:root ."
    cwd node['cookbook-openshift3']['openshift_node_config_dir']
    action :nothing
  end

  directory "Fix permissions on #{node['cookbook-openshift3']['openshift_node_config_dir']}" do
    path node['cookbook-openshift3']['openshift_node_config_dir']
    owner 'root'
    group 'root'
    mode '0755'
  end

  file "Fix permissions on #{node['cookbook-openshift3']['openshift_node_config_dir']}/ca.crt" do
    path ::File.join(node['cookbook-openshift3']['openshift_node_config_dir'], 'ca.crt')
    owner 'root'
    group 'root'
    mode '0644'
  end

  remote_file '/etc/pki/ca-trust/source/anchors/openshift-ca.crt' do
    source "file://#{node['cookbook-openshift3']['openshift_node_config_dir']}/ca.crt"
    notifies :run, 'ruby_block[Update ca trust]', :immediately
    sensitive true
  end

  # Use ruby_block for copying OpenShift CA to system CA trust
  ruby_block 'Update ca trust' do
    block do
      Mixlib::ShellOut.new('update-ca-trust').run_command
    end
    notifies :restart, 'service[docker]', :immediately if node['cookbook-openshift3']['deploy_containerized']
    notifies :run, 'execute[Wait for 30 seconds for docker services to come up]', :immediately
    action :nothing
  end

  execute 'Wait for 30 seconds for docker services to come up' do
    command 'sleep 30'
    action :nothing
    only_if { node['cookbook-openshift3']['deploy_containerized'] }
    not_if { node['cookbook-openshift3']['upgrade'] }
  end

  if node['cookbook-openshift3']['deploy_dnsmasq']
    package 'NetworkManager' do
      retries 3
    end

    template '/etc/origin/node/node-dnsmasq.conf' do
      source 'node-dnsmasq.conf.erb'
      only_if { ose_major_version.split('.')[1].to_i >= 6 }
    end

    template '/etc/dnsmasq.d/origin-dns.conf' do
      source 'origin-dns.conf.erb'
      variables(
        ose_major_version: ose_major_version
      )
      notifies :restart, 'service[dnsmasq]', :immediately
    end

    # On some systems, NetworkManager does not exist, so ignore_failure.
    cookbook_file '/etc/NetworkManager/dispatcher.d/99-origin-dns.sh' do
      source '99-origin-dns.sh'
      owner 'root'
      group 'root'
      mode '0755'
      action :create
      ignore_failure true
      notifies :restart, 'service[NetworkManager]', :immediately
    end

    ruby_block 'Setup dnsmasq' do
      block do
        f = Chef::Util::FileEdit.new('/etc/dnsmasq.conf')
        f.insert_line_if_no_match(%r{^conf-dir=/etc/dnsmasq.d}, 'conf-dir=/etc/dnsmasq.d')
        f.write_file
      end
    end

    # ignore_failure in case this fails/is not necessary
    service 'dnsmasq' do
      action %i(enable start)
      ignore_failure true
    end

    ruby_block 'Enforce running NM_CONTROLLED on host (>= 3.6)' do
      block do
        f = Chef::Util::FileEdit.new("/etc/sysconfig/network-scripts/ifcfg-#{node['network']['default_interface']}")
        f.search_file_delete_line(/^NM_CONTROLLED/)
        f.write_file
      end
      notifies :restart, 'service[NetworkManager]', :immediately
      only_if { ::File.exist?("/etc/sysconfig/network-scripts/ifcfg-#{node['network']['default_interface']}") }
      only_if { ose_major_version.split('.')[1].to_i >= 6 }
    end
  end

  template node['cookbook-openshift3']['openshift_node_config_file'] do
    source 'node.yaml.erb'
    variables(
      node_labels: node_servers.find { |server_node| server_node['fqdn'] == node['fqdn'] }['labels'].to_s.split(' '),
      ose_major_version: ose_major_version,
      kubelet_args: node['cookbook-openshift3']['openshift_node_kubelet_args_default'].merge(node['cookbook-openshift3']['openshift_node_kubelet_args_custom'])
    )
    notifies :run, 'execute[daemon-reload]', :immediately
    notifies :restart, 'service[Restart Node]', :immediately
    notifies :enable, "systemd_unit[#{node['cookbook-openshift3']['openshift_service_type']}-node]", :immediately
  end

  selinux_policy_boolean 'virt_use_nfs' do
    value true
  end

  execute 'Wait for API to become available before starting Node component' do
    command "[[ $(curl --silent ${MASTER_URL}/healthz/ready --cacert #{node['cookbook-openshift3']['openshift_node_config_dir']}/ca.crt) =~ \"ok\" ]]"
    environment 'MASTER_URL' => node['cookbook-openshift3']['openshift_HA'] ? node['cookbook-openshift3']['openshift_master_api_url'] : "https://#{first_master['fqdn']}:#{node['cookbook-openshift3']['openshift_master_api_port']}"
    retries 120
    retry_delay 1
    notifies :start, 'service[Restart Node]', :immediately unless node['cookbook-openshift3']['upgrade'] && node['cookbook-openshift3']['deploy_containerized']
    notifies :restart, 'service[Restart Node]', :immediately if node['cookbook-openshift3']['upgrade'] && node['cookbook-openshift3']['deploy_containerized']
  end
end
