#
# Cookbook Name:: cookbook-openshift3
# Recipe:: upgrade_control_plane37_part2
#
# Copyright (c) 2015 The Authors, All Rights Reserved.

# This must be run before any upgrade takes place.
# It creates the service signer certs (and any others) if they were not in
# existence previously.

server_info = OpenShiftHelper::NodeHelper.new(node)
first_etcd = server_info.first_etcd
is_master_server = server_info.on_master_server?
is_node_server = server_info.on_node_server?
is_first_master = server_info.on_first_master?
master_servers = server_info.master_servers

hosted_upgrade_version = node['cookbook-openshift3']['deploy_containerized'] == true ? node['cookbook-openshift3']['openshift_docker_image_version'] : 'v' + node['cookbook-openshift3']['ose_version'].to_s.split('-')[0]

if is_master_server && is_first_master
  log 'Pre master upgrade - Upgrade all storage' do
    level :info
  end

  execute 'Confirm OpenShift authorization objects are in sync' do
    command "#{node['cookbook-openshift3']['openshift_common_admin_binary']} \
            --config=#{node['cookbook-openshift3']['openshift_master_config_dir']}/admin.kubeconfig \
            migrate authorization"
    not_if "#{node['cookbook-openshift3']['openshift_common_client_binary']} version | grep -w v3.7"
  end

  execute 'Migrate storage post policy reconciliation' do
    command "#{node['cookbook-openshift3']['openshift_common_admin_binary']} \
            --config=#{node['cookbook-openshift3']['openshift_master_config_dir']}/admin.kubeconfig \
            migrate storage --include=* --confirm"
    not_if "#{node['cookbook-openshift3']['openshift_common_client_binary']} version | grep -w v3.7"
  end

  execute 'Create key for upgrade all storage' do
    command "ETCDCTL_API=3 /usr/bin/etcdctl --cert #{node['cookbook-openshift3']['etcd_peer_file']} --key #{node['cookbook-openshift3']['etcd_peer_key']} --cacert #{node['cookbook-openshift3']['etcd_ca_cert']} --endpoints https://`hostname`:2379 put migration ok"
    not_if "#{node['cookbook-openshift3']['openshift_common_client_binary']} version | grep -w v3.7"
  end
end

if is_master_server && !is_first_master
  execute 'Wait for First master to upgrade all storage' do
    command "ETCDCTL_API=3 /usr/bin/etcdctl --cert #{node['cookbook-openshift3']['etcd_peer_file']} --key #{node['cookbook-openshift3']['etcd_peer_key']} --cacert #{node['cookbook-openshift3']['etcd_ca_cert']} --endpoints https://`hostname`:2379 get migration -w simple | grep -w ok"
    retries 120
    retry_delay 5
    not_if "#{node['cookbook-openshift3']['openshift_common_client_binary']} version | grep -w v3.7"
  end
end

if is_master_server
  log 'Upgrade for MASTERS [STARTED]' do
    level :info
  end

  log 'Stop all master services prior to upgrade for 3.6 to 3.7 transition' do
    level :info
    notifies :stop, "service[#{node['cookbook-openshift3']['openshift_service_type']}-master-api]", :immediately
    notifies :stop, "service[#{node['cookbook-openshift3']['openshift_service_type']}-master-controllers]", :immediately
    not_if { master_servers.size == 1 }
    not_if "#{node['cookbook-openshift3']['openshift_common_client_binary']} version | grep -w v3.7"
  end

  include_recipe 'cookbook-openshift3::certificate_server' if node['cookbook-openshift3']['deploy_containerized']

  include_recipe 'cookbook-openshift3::master_cluster'

  include_recipe 'cookbook-openshift3::node' if is_node_server

  log 'Restart Master & Node services' do
    level :info
    notifies :restart, "service[#{node['cookbook-openshift3']['openshift_service_type']}-master]", :immediately unless node['cookbook-openshift3']['openshift_HA']
    notifies :restart, "service[#{node['cookbook-openshift3']['openshift_service_type']}-master-api]", :immediately if node['cookbook-openshift3']['openshift_HA']
    notifies :restart, "service[#{node['cookbook-openshift3']['openshift_service_type']}-master-controllers]", :immediately if node['cookbook-openshift3']['openshift_HA']
    notifies :restart, "service[#{node['cookbook-openshift3']['openshift_service_type']}-node]", :immediately
    notifies :restart, 'service[openvswitch]', :immediately if is_node_server
  end

  execute "Set upgrade markup for master : #{node['fqdn']}" do
    command "/usr/bin/etcdctl --cert-file #{node['cookbook-openshift3']['openshift_master_config_dir']}/master.etcd-client.crt --key-file #{node['cookbook-openshift3']['openshift_master_config_dir']}/master.etcd-client.key --ca-file #{node['cookbook-openshift3']['openshift_master_config_dir']}/master.etcd-ca.crt -C https://#{first_etcd['ipaddress']}:2379 set /migration/#{node['cookbook-openshift3']['control_upgrade_version']}/#{node['fqdn']} ok"
  end

  log 'Upgrade for MASTERS [COMPLETED]' do
    level :info
  end
end

if is_master_server && !is_first_master
  execute 'Wait for First master to reconcile all roles' do
    command "[[ $(ETCDCTL_API=3 /usr/bin/etcdctl --cert #{node['cookbook-openshift3']['etcd_peer_file']} --key #{node['cookbook-openshift3']['etcd_peer_key']} --cacert #{node['cookbook-openshift3']['etcd_ca_cert']} --endpoints https://`hostname`:2379 get migration -w simple | wc -l) -eq 0 ]]"
    retries 120
    retry_delay 5
  end
end

if is_master_server && is_first_master

  execute 'Wait for API to be ready' do
    command "[[ $(curl --silent #{node['cookbook-openshift3']['openshift_master_api_url']}/healthz/ready --cacert #{node['cookbook-openshift3']['openshift_master_config_dir']}/ca.crt --cacert #{node['cookbook-openshift3']['openshift_master_config_dir']}/ca-bundle.crt) =~ \"ok\" ]]"
    retries 120
    retry_delay 1
  end

  log 'Reconcile Cluster Roles & Cluster Role Bindings [STARTED]' do
    level :info
  end

  execute 'Remove shared-resource-viewer protection before upgrade' do
    command "#{node['cookbook-openshift3']['openshift_common_client_binary']} \
            --config=#{node['cookbook-openshift3']['openshift_master_config_dir']}/admin.kubeconfig \
            annotate role shared-resource-viewer openshift.io/reconcile-protect- -n openshift"
  end

  execute 'Reconcile Security Context Constraints' do
    command "#{node['cookbook-openshift3']['openshift_common_admin_binary']} \
            --config=#{node['cookbook-openshift3']['openshift_master_config_dir']}/admin.kubeconfig \
            policy reconcile-sccs --confirm --additive-only=true"
  end

  execute 'Migrate storage post policy reconciliation' do
    command "#{node['cookbook-openshift3']['openshift_common_admin_binary']} \
            --config=#{node['cookbook-openshift3']['openshift_master_config_dir']}/admin.kubeconfig \
            migrate storage --include=* --confirm"
  end

  execute 'Delete key for upgrade all storage' do
    command "ETCDCTL_API=3 /usr/bin/etcdctl --cert #{node['cookbook-openshift3']['etcd_peer_file']} --key #{node['cookbook-openshift3']['etcd_peer_key']} --cacert #{node['cookbook-openshift3']['etcd_ca_cert']} --endpoints https://`hostname`:2379 del migration"
  end
end

if is_master_server
  log 'Cycle all controller services to force new leader election mode' do
    level :info
    notifies :restart, "service[#{node['cookbook-openshift3']['openshift_service_type']}-master-controllers]", :immediately
  end

  log 'Reconcile Cluster Roles & Cluster Role Bindings [COMPLETED]' do
    level :info
  end
end

if is_master_server && is_first_master
  log 'Update hosted deployment(s) to current version [STARTED]' do
    level :info
  end

  ruby_block 'Get current router image' do
    block do
      node.run_state['router_image'] = Mixlib::ShellOut.new("#{node['cookbook-openshift3']['openshift_common_client_binary']} get dc/router -n #{node['cookbook-openshift3']['openshift_hosted_router_namespace']} -o jsonpath='{.spec.template.spec.containers[0].image}'").run_command.stdout.strip
    end
    only_if do
      node['cookbook-openshift3']['openshift_hosted_manage_router']
    end
  end

  ruby_block 'Get current registry image' do
    block do
      node.run_state['registry_image'] = Mixlib::ShellOut.new("#{node['cookbook-openshift3']['openshift_common_client_binary']} get dc/docker-registry -n #{node['cookbook-openshift3']['openshift_hosted_registry_namespace']} -o jsonpath='{.spec.template.spec.containers[0].image}'").run_command.stdout.strip
    end
    only_if do
      node['cookbook-openshift3']['openshift_hosted_manage_registry']
    end
  end

  execute "Update router image to current version \"#{hosted_upgrade_version}\"" do
    command lazy {
      "#{node['cookbook-openshift3']['openshift_common_client_binary']} \
      --config=#{node['cookbook-openshift3']['openshift_master_config_dir']}/admin.kubeconfig \
      patch dc/router -n #{node['cookbook-openshift3']['openshift_hosted_router_namespace']} -p \
      \'{\"spec\":{\"template\":{\"spec\":{\"containers\":[{\"name\":\"router\",\"image\":\"#{node.run_state['router_image'].gsub(/:v.+/, ":#{hosted_upgrade_version}")}\",\"livenessProbe\":{\"tcpSocket\":null,\"httpGet\":{\"path\": \"/healthz\", \"port\": 1936, \"host\": \"localhost\", \"scheme\": \"HTTP\"},\"initialDelaySeconds\":10,\"timeoutSeconds\":1}}]}}}}'"
    }
    only_if do
      node['cookbook-openshift3']['openshift_hosted_manage_router']
    end
  end

  execute "Update registry image to current version \"#{hosted_upgrade_version}\"" do
    command lazy {
      "#{node['cookbook-openshift3']['openshift_common_client_binary']} \
      --config=#{node['cookbook-openshift3']['openshift_master_config_dir']}/admin.kubeconfig \
      patch dc/docker-registry -n #{node['cookbook-openshift3']['openshift_hosted_registry_namespace']} -p \
      \'{\"spec\":{\"template\":{\"spec\":{\"containers\":[{\"name\":\"registry\",\"image\":\"#{node.run_state['registry_image'].gsub(/:v.+/, ":#{hosted_upgrade_version}")}\"}]}}}}'"
    }
    only_if do
      node['cookbook-openshift3']['openshift_hosted_manage_registry']
    end
  end

  log 'Update hosted deployment(s) to current version [COMPLETED]' do
    level :info
  end
end
