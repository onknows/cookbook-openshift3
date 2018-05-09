default['is_apaas_openshift_cookbook']['openshift_adhoc_reboot_node'] = false

default['is_apaas_openshift_cookbook']['adhoc_redeploy_certificates'] = false
default['is_apaas_openshift_cookbook']['adhoc_redeploy_etcd_ca'] = false
default['is_apaas_openshift_cookbook']['adhoc_redeploy_cluster_ca'] = false

default['is_apaas_openshift_cookbook']['redeploy_etcd_ca_control_flag'] = '/to_be_replaced_ca_etcd'
default['is_apaas_openshift_cookbook']['redeploy_etcd_certs_control_flag'] = '/to_be_replaced_certs'

default['is_apaas_openshift_cookbook']['redeploy_cluster_ca_certserver_control_flag'] = '/to_be_replaced_ca_cluster'
default['is_apaas_openshift_cookbook']['redeploy_cluster_ca_masters_control_flag'] = '/to_be_replaced_masters'
default['is_apaas_openshift_cookbook']['redeploy_cluster_ca_nodes_control_flag'] = '/to_be_replaced_nodes'
default['is_apaas_openshift_cookbook']['redeploy_cluster_hosted_certserver_control_flag'] = '/to_be_replaced_hosted_cluster'

default['is_apaas_openshift_cookbook']['adhoc_uninstall_control_flag'] = '/root/uninstall_node'
