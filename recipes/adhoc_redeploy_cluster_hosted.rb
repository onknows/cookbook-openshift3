#
# Cookbook Name:: cookbook-openshift3
# Recipe:: adhoc_redeploy_cluster_hosted
#
# Copyright (c) 2015 The Authors, All Rights Reserved.

Chef::Log.warn("The CLUSTER HOSTED CERTS redeploy will be skipped on First master. Could not find the flag: #{node['cookbook-openshift3']['redeploy_cluster_hosted_certserver_control_flag']}") unless ::File.file?(node['cookbook-openshift3']['redeploy_cluster_hosted_certserver_control_flag'])

if ::File.file?(node['cookbook-openshift3']['redeploy_cluster_hosted_certserver_control_flag'])

  execute 'Wait for 10 seconds whilst updating ENV' do
    command 'sleep 10'
    action :nothing
  end

  if node['cookbook-openshift3']['openshift_hosted_manage_registry']
    execute 'Re-Generate Cluster CA certificates for Hosted Registry' do
      command "#{node['cookbook-openshift3']['openshift_common_client_binary']} env dc/docker-registry OPENSHIFT_CA_DATA=\"$(cat ca.crt)\" OPENSHIFT_CERT_DATA=\"$(cat openshift-registry.crt)\" OPENSHIFT_KEY_DATA=\"$(cat openshift-registry.key)\" -n ${namespace_registry} --config=admin.kubeconfig"
      environment(
        'namespace_registry' => node['cookbook-openshift3']['openshift_hosted_registry_namespace']
      )
      cwd node['cookbook-openshift3']['openshift_master_config_dir']
      only_if "#{node['cookbook-openshift3']['openshift_common_client_binary']} env dc/docker-registry --list -n ${namespace_registry} --config=#{node['cookbook-openshift3']['openshift_master_config_dir']}/admin.kubeconfig | grep OPENSHIFT_CA_DATA"
      notifies :run, 'execute[Wait for 10 seconds whilst updating ENV]', :immediately
    end

    execute 'Re-Generate certificates for Hosted Registry' do
      command "#{node['cookbook-openshift3']['openshift_common_client_binary']} adm ca create-server-cert --signer-cert=#{node['cookbook-openshift3']['openshift_master_config_dir']}/ca.crt --signer-key=#{node['cookbook-openshift3']['openshift_master_config_dir']}/ca.key --signer-serial=#{node['cookbook-openshift3']['openshift_master_config_dir']}/ca.serial.txt --hostnames=\"$(#{node['cookbook-openshift3']['openshift_common_client_binary']} get service docker-registry -o jsonpath='{.spec.clusterIP}' --config=#{node['cookbook-openshift3']['openshift_master_config_dir']}/admin.kubeconfig -n #{node['cookbook-openshift3']['openshift_hosted_registry_namespace']}),docker-registry.#{node['cookbook-openshift3']['openshift_hosted_registry_namespace']}.svc.cluster.local,${docker_registry_route_hostname}\" --cert=#{node['cookbook-openshift3']['openshift_master_config_dir']}/registry.crt --key=#{node['cookbook-openshift3']['openshift_master_config_dir']}/registry.key --config=#{node['cookbook-openshift3']['openshift_master_config_dir']}/admin.kubeconfig"
      environment lazy {
        {
          'registry_svc_ip' => `#{node['cookbook-openshift3']['openshift_common_client_binary']} get service docker-registry -o jsonpath='{.spec.clusterIP}' --config=#{node['cookbook-openshift3']['openshift_master_config_dir']}/admin.kubeconfig -n #{node['cookbook-openshift3']['openshift_hosted_registry_namespace']}`,
          'docker_registry_route_hostname' => "docker-registry-#{node['cookbook-openshift3']['openshift_hosted_registry_namespace']}-#{node['cookbook-openshift3']['openshift_master_router_subdomain']}"
        }
      }
      cwd node['cookbook-openshift3']['openshift_master_config_dir']
    end

    execute 'Re-Create secret for certificates' do
      command "#{node['cookbook-openshift3']['openshift_common_client_binary']} secrets new registry-certificates #{node['cookbook-openshift3']['openshift_master_config_dir']}/registry.crt #{node['cookbook-openshift3']['openshift_master_config_dir']}/registry.key -n ${namespace_registry} --config=#{node['cookbook-openshift3']['openshift_master_config_dir']}/admin.kubeconfig -o json | #{node['cookbook-openshift3']['openshift_common_client_binary']} replace -n ${namespace_registry} -f -"
      environment lazy {
        {
          'registry_svc_ip' => `#{node['cookbook-openshift3']['openshift_common_client_binary']} get service docker-registry -o jsonpath='{.spec.clusterIP}' --config=#{node['cookbook-openshift3']['openshift_master_config_dir']}/admin.kubeconfig -n #{node['cookbook-openshift3']['openshift_hosted_registry_namespace']}`,
          'namespace_registry' => node['cookbook-openshift3']['openshift_hosted_registry_namespace'],
          'docker_registry_route_hostname' => "docker-registry-#{node['cookbook-openshift3']['openshift_hosted_registry_namespace']}-#{node['cookbook-openshift3']['openshift_master_router_subdomain']}"
        }
      }
      cwd node['cookbook-openshift3']['openshift_master_config_dir']
    end

    execute 'Redeploy docker registry' do
      command "#{node['cookbook-openshift3']['openshift_common_client_binary']} deploy dc/docker-registry --latest -n ${namespace_registry} --config=admin.kubeconfig"
      environment(
        'namespace_registry' => node['cookbook-openshift3']['openshift_hosted_registry_namespace']
      )
      retries 2
      retry_delay 10
      ignore_failure true
      cwd node['cookbook-openshift3']['openshift_master_config_dir']
    end
  end

  if node['cookbook-openshift3']['openshift_hosted_manage_router']
    execute 'Re-Generate Cluster CA certificates for Hosted Router' do
      command "#{node['cookbook-openshift3']['openshift_common_client_binary']} env dc/router OPENSHIFT_CA_DATA=\"$(cat ca.crt)\" OPENSHIFT_CERT_DATA=\"$(cat openshift-router.crt)\" OPENSHIFT_KEY_DATA=\"$(cat openshift-router.key)\" -n ${namespace_router} --config=admin.kubeconfig"
      environment(
        'namespace_router' => node['cookbook-openshift3']['openshift_hosted_router_namespace']
      )
      cwd node['cookbook-openshift3']['openshift_master_config_dir']
      only_if "#{node['cookbook-openshift3']['openshift_common_client_binary']} env dc/router --list -n ${namespace_router} --config=#{node['cookbook-openshift3']['openshift_master_config_dir']}/admin.kubeconfig | grep OPENSHIFT_CA_DATA"
      notifies :run, 'execute[Wait for 10 seconds whilst updating ENV]', :immediately
    end

    execute 'Delete existing certificate' do
      command "#{node['cookbook-openshift3']['openshift_common_client_binary']} $ACTION secret/router-certs --ignore-not-found -n ${namespace_router} --config=admin.kubeconfig"
      environment(
        'namespace_router' => node['cookbook-openshift3']['openshift_hosted_router_namespace'],
        'ACTION' => 'delete'
      )
      cwd node['cookbook-openshift3']['openshift_master_config_dir']
      notifies :run, 'execute[Wait for 10 seconds whilst updating ENV]', :immediately
    end

    execute 'Remove router service annotations' do
      command "#{node['cookbook-openshift3']['openshift_common_client_binary']} annotate service/router service.alpha.openshift.io/serving-cert-secret-name- service.alpha.openshift.io/serving-cert-signed-by- -n ${namespace_router}"
      environment(
        'namespace_router' => node['cookbook-openshift3']['openshift_hosted_router_namespace']
      )
    end

    execute 'Add serving-cert-secret annotation to router service' do
      command "#{node['cookbook-openshift3']['openshift_common_client_binary']} annotate service/router service.alpha.openshift.io/serving-cert-secret-name=router-certs -n ${namespace_router}"
      environment(
        'namespace_router' => node['cookbook-openshift3']['openshift_hosted_router_namespace']
      )
    end

    execute 'Create Hosted Router Certificate' do
      command "#{node['cookbook-openshift3']['openshift_common_client_binary']} secrets new router-certs --type=kubernetes.io/tls tls.crt=${certfile} tls.key=${keyfile} -n ${namespace_router} --confirm"
      environment(
        'certfile' => node['cookbook-openshift3']['openshift_hosted_router_certfile'],
        'keyfile' => node['cookbook-openshift3']['openshift_hosted_router_keyfile'],
        'namespace_router' => node['cookbook-openshift3']['openshift_hosted_router_namespace']
      )
      cwd node['cookbook-openshift3']['openshift_master_config_dir']
    end

    execute 'Redeploy router' do
      command "#{node['cookbook-openshift3']['openshift_common_client_binary']} deploy dc/router --latest -n ${namespace_router} --config=admin.kubeconfig"
      environment(
        'namespace_router' => node['cookbook-openshift3']['openshift_hosted_router_namespace']
      )
      retries 2
      retry_delay 10
      cwd node['cookbook-openshift3']['openshift_master_config_dir']
      ignore_failure true
    end
  end

  file node['cookbook-openshift3']['redeploy_cluster_hosted_certserver_control_flag'] do
    action :delete
  end
end
