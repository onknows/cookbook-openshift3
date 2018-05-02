# Redeploy Platform Certificates Process

### Overview

You can use the `cookbook-openshift3::adhoc_redeploy_certificates` recipe to
automate the ETCD/OpenShift cluster certificates renewal.

#### Certificate renewal

The following table is a guide for renewing the certificates:

| PURPOSE | Supported | Variable | Control Flag |
| ------------------------------- | ------------------ | ---------- | ----------- |
| Redeploying a New etcd CA Only | `Fully`    | `adhoc_redeploy_etcd_ca` | `redeploy_etcd_ca_control_flag` |
| Redeploying etcd Server Certificates (ETCD) Only | `Fully` |`adhoc_redeploy_etcd_ca` | `redeploy_etcd_certs_control_flag` |
| Redeploying etcd Client Certificates (MASTERS) Only | `Fully` |`adhoc_redeploy_etcd_ca` | `redeploy_etcd_certs_control_flag` |
| Redeploying a New OCP Cluster CA Only | `Fully`  | `adhoc_redeploy_cluster_ca` | `redeploy_cluster_ca_certserver_control_flag` |
| Redeploying Master Certificates Only | `Fully`  | `adhoc_redeploy_cluster_ca` | `redeploy_cluster_ca_masters_control_flag` |
| Redeploying Node Certificates Only | `Fully` | `adhoc_redeploy_cluster_ca` | `redeploy_cluster_ca_nodes_control_flag` |
| Redeploying Registry Certificates Only | `Fully` | `adhoc_redeploy_cluster_ca` | `redeploy_cluster_hosted_certserver_control_flag` |
| Redeploying Router Certificates Only | `Fully` | `adhoc_redeploy_cluster_ca` | `redeploy_cluster_hosted_certserver_control_flag` |

#### Control Renewal of certificates

When renewing the certificates in separate phases (CA/CERTS), the control phase
includes:

* The `adhoc_redeploy_etcd_ca` redeploys the etcd CA certificate by generating a
new CA certificate and distributing and generate a bundle containing old and new
to all etcd peers and master clients (CERTIFICATE SERVER).

* The `adhoc_redeploy_cluster_ca` redeploys the OCP CA certificate by generating
a new CA certificate and distributing and generate a bundle containing old and
new to all master and node clients (CERTIFICATE SERVER). 

The control flag `redeploy_cluster_ca_masters_control_flag` redeploys new
certificates signed by CA certificate and distributing to all master servers.
The control flag `redeploy_cluster_ca_nodes_control_flag` redeploys new
certificates signed by CA certificate and distributing to all node servers. The
control flag `redeploy_cluster_hosted_certserver_control_flag` redeploys new
certificates for registry and router hosted components signed by CA certificate
from the first master server.
