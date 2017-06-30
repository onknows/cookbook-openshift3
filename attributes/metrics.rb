default['cookbook-openshift3']['openshift_hosted_metrics_storage_kind'] = 'emptydir'
default['cookbook-openshift3']['openshift_hosted_metrics_storage_volume_size'] = '10Gi'
default['cookbook-openshift3']['openshift_hosted_metrics_storage_volume_name'] = 'metrics-cassandra'
default['cookbook-openshift3']['openshift_hosted_metrics_storage_access_modes'] = "['ReadWriteOnce']"

default['cookbook-openshift3']['openshift_metrics_image_prefix'] = node['cookbook-openshift3']['openshift_deployment_type'] =~ /enterprise/ ? 'registry.access.redhat.com/openshift3/' : 'docker.io/openshift/origin-'
default['cookbook-openshift3']['openshift_metrics_image_version'] = node['cookbook-openshift3']['openshift_deployment_type'] =~ /enterprise/ ? '3.5.0' : 'latest'

default['cookbook-openshift3']['openshift_metrics_start_cluster'] = true
default['cookbook-openshift3']['openshift_metrics_install_metrics'] = true
default['cookbook-openshift3']['openshift_metrics_startup_timeout'] = '500'
default['cookbook-openshift3']['openshift_metrics_hawkular_replicas'] = '1'
default['cookbook-openshift3']['openshift_metrics_hawkular_limits_memory'] = '2.5G'
default['cookbook-openshift3']['openshift_metrics_hawkular_limits_cpu'] = nil
default['cookbook-openshift3']['openshift_metrics_hawkular_requests_memory'] = '1.5G'
default['cookbook-openshift3']['openshift_metrics_hawkular_requests_cpu'] = nil
default['cookbook-openshift3']['openshift_metrics_hawkular_cert'] = ''
default['cookbook-openshift3']['openshift_metrics_hawkular_key'] = ''
default['cookbook-openshift3']['openshift_metrics_hawkular_ca'] = ''
default['cookbook-openshift3']['openshift_metrics_hawkular_nodeselector'] = %w()
default['cookbook-openshift3']['openshift_metrics_cassandra_replicas'] = '1'
default['cookbook-openshift3']['openshift_metrics_cassandra_storage_type'] = node['cookbook-openshift3']['openshift_hosted_metrics_storage_kind']
default['cookbook-openshift3']['openshift_metrics_cassandra_pvc_size'] = node['cookbook-openshift3']['openshift_hosted_metrics_storage_volume_size']
default['cookbook-openshift3']['openshift_metrics_cassandra_limits_memory'] = '2G'
default['cookbook-openshift3']['openshift_metrics_cassandra_limits_cpu'] = nil
default['cookbook-openshift3']['openshift_metrics_cassandra_requests_memory'] = '1G'
default['cookbook-openshift3']['openshift_metrics_cassandra_requests_cpu'] = nil
default['cookbook-openshift3']['openshift_metrics_cassandra_nodeselector'] = %w()
default['cookbook-openshift3']['openshift_metrics_cassandra_storage_group'] = '65534'
default['cookbook-openshift3']['openshift_metrics_heapster_standalone'] = false
default['cookbook-openshift3']['openshift_metrics_heapster_limits_memory'] = '3.75G'
default['cookbook-openshift3']['openshift_metrics_heapster_limits_cpu'] = nil
default['cookbook-openshift3']['openshift_metrics_heapster_requests_memory'] = '0.9375G'
default['cookbook-openshift3']['openshift_metrics_heapster_requests_cpu'] = nil
default['cookbook-openshift3']['openshift_metrics_heapster_nodeselector'] = %w()
default['cookbook-openshift3']['openshift_metrics_hawkular_hostname'] = "hawkular-metrics.#{node['cookbook-openshift3']['openshift_master_router_subdomain']}"
default['cookbook-openshift3']['openshift_metrics_duration'] = '7'
default['cookbook-openshift3']['openshift_metrics_resolution'] = '30s'
default['cookbook-openshift3']['openshift_metrics_master_url'] = 'https://kubernetes.default.svc.cluster.local'
default['cookbook-openshift3']['openshift_metrics_node_id'] = 'nodename'
default['cookbook-openshift3']['openshift_metrics_project'] = 'openshift-infra'
default['cookbook-openshift3']['openshift_metrics_cassandra_pvc_prefix'] = node['cookbook-openshift3']['openshift_hosted_metrics_storage_volume_name']
default['cookbook-openshift3']['openshift_metrics_cassandra_pvc_access'] = node['cookbook-openshift3']['openshift_hosted_metrics_storage_access_modes']
default['cookbook-openshift3']['openshift_metrics_hawkular_user_write_access'] = false
default['cookbook-openshift3']['openshift_metrics_heapster_allowed_users'] = 'system:master-proxy'
