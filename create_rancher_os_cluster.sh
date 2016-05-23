#!/bin/bash
# Author - John Knepper
# Date   - March 19, 2016

# Spin Rancher COREOS cluster with Rancher installed.

# Modify ~/.aws/credentials file to container appropriate region, or 
# update your .bashrc to set / export your AWS keys appropriately.
# Launch Rancher MASTER and provide URL or IP to master.

# USAGE: ./create_rancher_os_cluster.sh 
usage () {
  echo "./create_rancher_os_cluster.sh \ 
        -a <slave ami id> \
        -g <security group id> \
        -h <hosted zone ID form R53> \
        -n <name> \
        -k <key name> \
        -t <instance type>
        -u <master ip> \
        -v <vpc id> \
        -x <slave count> \
        -y <rancher generated security token from rancher master ui \
        -z <subnet id>"
   exit
}

# NOTES - This will spin up a CoreOS cluster, connect the nodes, and connect them to a Rancher Master instance:

while getopts ":n:v:a:z:h:x:u:g:t:y:k:" o; do
    case "${o}" in
        a)
            a=${OPTARG}
            ;;
        g)
            g=${OPTARG}
            ;;
        h)
            h=${OPTARG}
            ;;
        k)
            k=${OPTARG}
            ;;
        n)
            n=${OPTARG}
            ;;
        t)
            t=${OPTARG}
            ;;
        u)
            u=${OPTARG}
            ;;
        v)
            v=${OPTARG}
            ;;
        x)
            x=${OPTARG}
            ;;
        y)
            y=${OPTARG}
            ;;
        z)
            z=${OPTARG}
            ;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

if [ -z "${n}" ] || [ -z "${v}" ] || [ -z "${a}" ] || [ -z "${z}" ] || [ -z "${h}" ] || [ -z "${x}" ] || [ -z "${u}" ] || [ -z "${g}" ] || [ -z "${t}" ] || [ -z "${y}" ] || [ -z "${k}" ]; then
    usage
fi

# See if LC exists:
aws autoscaling describe-launch-configurations --launch-configuration-names "$n" | grep LaunchConfigurationName | wc -l > t
export lc_exists=`cat t`

# If exists, move on.  Otherwise, create LC:
if [ $lc_exists -ne 0 ]; then
  echo "LC $n exists!  Moving on."
else
  echo "LC $n Does not exist.  Standing up Rancher architecture \
        LC  - $n-slaves-lc $n-master-lc \
        ASG - $n-slaves-asg $n-master-asg \
        ELB - $n-slaves-lb $n-master-lb \
        R53 - $n-cluster.knepper.co $n-master.knepper.co
       "

  # STANDUP COREOS CLUSTER:

  # Add unique etcd discovery url token / query string in coreos userdata file:
  export etcd_string=`curl -w "\n" "https://discovery.etcd.io/new?size=${x}" | cut -f4 -d"/"`
  sed -i '' "s/etcd-token/${etcd_string}/g" coreos-userdata.yml 

  # Add label from name argument on cml:
  sed -i '' "s/label-token/Name=${n}/g" coreos-userdata.yml

  # sub out rancher  master IP address in rancher-agent.service for rancher agent:
  sed -i '' "s/mgmt-ip-token/${u}/g" coreos-userdata.yml

  # Sub in security token
  sed -i '' "s/SECURITY_TOKEN/${y}/g" coreos-userdata.yml

  # CoreOS LC w / PV us-west-1 (ami-a8aedfc8):
  aws autoscaling create-launch-configuration --launch-configuration-name $n-slaves-lc --image-id $a --instance-type $t --user-data file://coreos-userdata.yml --security-groups $g --key-name $k
  sleep 5

  # Create load balancer for ASG
  aws elb create-load-balancer --load-balancer-name "$n-slaves-lb" --listeners "Protocol=TCP,LoadBalancerPort=500,InstanceProtocol=TCP,InstancePort=500" "Protocol=TCP,LoadBalancerPort=4500,InstanceProtocol=TCP,InstancePort=4500" --subnets $z --security-groups $g
  sleep 5

  # Describe ELB FQDN:
  aws elb describe-load-balancers --load-balancer-name $n-slaves-lb | grep -i dnsname | sed 's/"DNSName"://' | sed 's/[",]//g' > t
  sleep 2
  export elb_fqdn=`cat t | sed -e 's/^[ \t]*//'`

  # sub out contents of change-resource-record-sets.json
  sed -i '' "s/hosted-zone-token/${h}/g" change-resource-record-sets.json
  sed -i '' "s/dns-token/${elb_fqdn}/g" change-resource-record-sets.json

  # Add to record:
  aws route53 change-resource-record-sets --hosted-zone-id $h --change-batch file://change-resource-record-sets.json
  sleep 5

  # Create ASG, and add load balancer:
  aws autoscaling create-auto-scaling-group --auto-scaling-group-name $n-slaves-asg --launch-configuration-name $n-slaves-lc --load-balancer-names $n-slaves-lb --health-check-type ELB --health-check-grace-period 120 --min-size $x --max-size $x --desired-capacity $x --vpc-zone-identifier $z
  sleep 5

  # cleanup...
  git checkout change-resource-record-sets.json
  git checkout coreos-userdata.yml
fi

