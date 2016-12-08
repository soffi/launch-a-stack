#!/bin/bash
set -x
#
# launch four machines, one proxy/approuter/loadbalancer with a firewall and "public" ip, the other ones are an appserver, messagequeue and a database server
# each instance uses a different template
#
# Set our credentials:
export AWS_ACCESS_KEY_ID=blibb
export AWS_SECRET_ACCESS_KEY=blobb
export AWS_DEFAULT_REGION=Local
# Set the endpoint to qstack
ENDPOINTURL=http://hybrid.qstack.

TEMPLATE_PROXY=qmi-...
TEMPLATE_APPSERVER=qmi-...
TEMPLATE_MQ=qmi-...
TEMPLATE_DB=qmi-...

# source stuff and override above if we don't want them
source ./overrides

# Set the name of the firewall
FWNAME=firewall
# Create firewall for the app router/loadbalancer
SGGROUPID=$(aws ec2 create-security-group --group-name $FWNAME --description firewall --endpoint-url $ENDPOINTURL --output text)
# Add rules to fw (this would be more cute with an array or a json that we can loop through)
# 
aws ec2 authorize-security-group-ingress --group-name $FWNAME --protocol tcp --port 22 --cidr 0.0.0.0/0 --endpoint-url $ENDPOINTURL 
aws ec2 authorize-security-group-ingress --group-name $FWNAME --protocol udp --port 53 --cidr 0.0.0.0/0 --endpoint-url $ENDPOINTURL 
aws ec2 authorize-security-group-ingress --group-name $FWNAME --protocol icmp --port -1 --cidr 0.0.0.0/0 --endpoint-url $ENDPOINTURL 
#
# create and start the proxy
ID_PROXY=$(aws ec2 run-instances --image-id $TEMPLATE_PROXY --instance-type m1.medium --security-group-ids $SGGROUPID --endpoint-url $ENDPOINTURL --output text| awk '/INSTANCE/{print $2}')
aws ec2 create-tags --resources $ID_PROXY --tags Key=name,Value=proxy --endpoint-url $ENDPOINTURL
# take a little nap so instance can get IP
sleep 10
# get the private IP of the proxy instance
aws ec2 describe-instances --instance-ids $ID_PROXY --endpoint-url $ENDPOINTURL --query "Reservations[*].Instances[*].PrivateIpAddress" --output=text > /tmp/privateip.txt
#
# build a userdata script ;-)
echo "#!/bin/bash" > /tmp/userdata
echo consul join $(cat /tmp/privateip.txt) >> /tmp/userdata
echo " ">> /tmp/userdata

# sleep for X seconds because the proxy has to start some services before other instances are launched
sleep 30

# create and start appserver
ID_APPSERVER=$(aws ec2 run-instances --image-id $TEMPLATE_APPSERVER --instance-type m1.medium --user-data file:///tmp/userdata --no-associate-public-ip-address --endpoint-url $ENDPOINTURL --output text| awk '/INSTANCE/{print $2}')
aws ec2 create-tags --resources $ID_APPSERVER --tags Key=name,Value=appserver --endpoint-url $ENDPOINTURL

# create and start mq
ID_MQ=$(aws ec2 run-instances --image-id $TEMPLATE_MQ --instance-type m1.medium --user-data file:///tmp/userdata --no-associate-public-ip-address --endpoint-url $ENDPOINTURL --output text| awk '/INSTANCE/{print $2}')
aws ec2 create-tags --resources $ID_MQ --tags Key=name,Value=mq --endpoint-url $ENDPOINTURL

# create and start database
ID_DB=$(aws ec2 run-instances --image-id $TEMPLATE_DB --instance-type m1.medium --user-data file:///tmp/userdata --no-associate-public-ip-address --endpoint-url $ENDPOINTURL --output text| awk '/INSTANCE/{print $2}')
aws ec2 create-tags --resources $ID_DB --tags Key=name,Value=db --endpoint-url $ENDPOINTURL


