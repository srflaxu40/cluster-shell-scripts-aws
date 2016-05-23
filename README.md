This will spin up a coreos cluster for rancher.  Inside the coreos-userdata.yml file are settings to start the rancher agent that connets an individual node to the master IP address, which is a command line parameter.
This is intended as a proof of concept for a multi-region system with Rancher.

USAGE:
`./create_rancher_os_cluster.sh -n jpop1 -v <VPC ID> -a <AMI ID>  -z <SUBNET ID> -h <HOSTED ZONE ID> -x 3 -u 52.53.231.164 -g <SECURITY GROUP ID> -t m3.medium -y <RANCHER GENERATED TOKEN>`

NOTE - your hosted zone, subnet, vpc, ami, and master IP address must already exist.  The usual way of adding nodes to the Rancher master is through the UI.  The discovery token above is unique, and will be unique for you too.  Navigate to the Rancher Master UI, click add hosts, and copy the trailing token on the string of the `docker run..` command.

HVM instance types are not supported below m3.medium's for coreos ami types.
