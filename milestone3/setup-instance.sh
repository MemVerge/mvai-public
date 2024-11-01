#!/bin/bash

echo "Welcome to the AWS EC2 + github setup script."
echo "This will start a g4dn.xlarge instance, sign in to github, and provide SSH access."

# Prompt user if they want to create a private key
read -p "Do you want to create a new private key? (y/n): " create_key
if [ "$create_key" == "y" ]; then
    aws ec2 create-key-pair --key-name GameOver --query "KeyMaterial" --output text > GameOver.pem
    chmod 400 GameOver.pem
    pkey="GameOver.pem"
else
    # Check for an existing .pem file
    pkey=$(ls *.pem 2>/dev/null | head -n 1)
    if [ -z "$pkey" ]; then
        echo "No .pem file found. Exiting."
        exit 1
    fi
fi

# Prompt user for the GitHub token path
read -p "Please provide the path to your GitHub token file for gh auth login. Must have repo, read:org, and gist permissions: " ghtoken
if [ ! -f "$ghtoken" ]; then
    echo "Token file not found at provided path. Exiting."
    exit 1
fi

# Prompt user if they want to create a new EC2 instance
read -p "Do you want to create a new EC2 instance? (y/n): " create_instance
if [ "$create_instance" == "y" ]; then
    # Delete existing security group if it exists
    aws ec2 delete-security-group --group-name "launch-wizard-4" 2>/dev/null

    # Create new security group
    aws ec2 create-security-group --no-paginate --group-name "launch-wizard-4" --description "launch-wizard-4 created $(date -u +"%Y-%m-%dT%H:%M:%SZ")" --vpc-id "vpc-0b17c2e4cb35375f7"
    
    # Retrieve security group ID
    sg_group_id=$(aws ec2 describe-security-groups --group-names launch-wizard-4 --query "SecurityGroups[0].GroupId" --output text)

    # Set up ingress and egress rules
    aws ec2 authorize-security-group-ingress --no-paginate --group-id $sg_group_id --ip-permissions '{"IpProtocol":"tcp","FromPort":22,"ToPort":22,"IpRanges":[{"CidrIp":"0.0.0.0/0"}]}' '{"IpProtocol":"tcp","FromPort":443,"ToPort":443,"IpRanges":[{"CidrIp":"0.0.0.0/0"}]}' '{"IpProtocol":"tcp","FromPort":80,"ToPort":80,"IpRanges":[{"CidrIp":"0.0.0.0/0"}]}' '{"IpProtocol":"tcp","FromPort":6443,"ToPort":6443,"IpRanges":[{"CidrIp":"0.0.0.0/0"}]}' '{"IpProtocol":"udp","FromPort":8472,"ToPort":8472,"IpRanges":[{"CidrIp":"0.0.0.0/0"}]}' '{"IpProtocol":"tcp","FromPort":10250,"ToPort":10250,"IpRanges":[{"CidrIp":"0.0.0.0/0"}]}'

    aws ec2 authorize-security-group-egress --no-paginate --group-id $sg_group_id --ip-permissions '{"IpProtocol":"tcp","FromPort":22,"ToPort":22,"IpRanges":[{"CidrIp":"0.0.0.0/0"}]}' '{"IpProtocol":"tcp","FromPort":443,"ToPort":443,"IpRanges":[{"CidrIp":"0.0.0.0/0"}]}' '{"IpProtocol":"tcp","FromPort":2376,"ToPort":2376,"IpRanges":[{"CidrIp":"0.0.0.0/0"}]}' '{"IpProtocol":"tcp","FromPort":6443,"ToPort":6443,"IpRanges":[{"CidrIp":"0.0.0.0/0"}]}'

    # Launch EC2 instance
    aws ec2 run-instances --no-paginate --image-id "ami-09961327ee867adb2" --instance-type "g4dn.xlarge" --key-name "GameOver" --block-device-mappings '{"DeviceName":"/dev/sda1","Ebs":{"Encrypted":false,"DeleteOnTermination":true,"Iops":3000,"SnapshotId":"snap-04dec20fe17265be6","VolumeSize":128,"VolumeType":"gp3","Throughput":125}}' --network-interfaces "{\"AssociatePublicIpAddress\":true,\"DeviceIndex\":0,\"Groups\":[\"$sg_group_id\"]}" --tag-specifications '{"ResourceType":"instance","Tags":[{"Key":"Name","Value":"mmai"}]}' --metadata-options '{"HttpEndpoint":"enabled","HttpPutResponseHopLimit":2,"HttpTokens":"required"}' --private-dns-name-options '{"HostnameType":"ip-name","EnableResourceNameDnsARecord":true,"EnableResourceNameDnsAAAARecord":false}' --count "1"
    
    # Retrieve instance DNS name
    dns_name=$(aws ec2 describe-instances --query "Reservations[0].Instances[0].PublicDnsName" --output text)
else
    # List existing instances and prompt user for choice
    echo "Listing existing instances:"
    aws ec2 describe-instances --query "Reservations[*].Instances[*].InstanceId" --output text
    read -p "Enter the Instance ID you want to connect to: " instance_id
    if [ -z "$instance_id" ]; then
        echo "No instance ID provided. Exiting."
        exit 1
    fi
    dns_name=$(aws ec2 describe-instances --instance-ids "$instance_id" --query "Reservations[0].Instances[0].PublicDnsName" --output text)
fi

# Copy GitHub token file to the instance
scp -i "$pkey" "$ghtoken" ubuntu@$dns_name:/home/ubuntu/ghtoken

# # Install GitHub CLI and authenticate
# ssh -i "$pkey" ubuntu@$dns_name -t "sudo snap install gh"
# ssh -i "$pkey" ubuntu@$dns_name -t "gh auth login --with-token < /home/ubuntu/ghtoken"
# # Install go
# ssh -i "$pkey" ubuntu@$dns_name -t "wget https://go.dev/dl/go1.23.2.linux-amd64.tar.gz"
# ssh -i "$pkey" ubuntu@$dns_name -t "sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf go1.23.2.linux-amd64.tar.gz"
# ssh -i "$pkey" ubuntu@$dns_name -t "echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc"
# # Install docker stack
# ssh -i "$pkey" ubuntu@$dns_name -t "sudo snap install docker"
# # Install some build tools
# ssh -i "$pkey" ubuntu@$dns_name -t "curl -sL https://raw.githubusercontent.com/creationix/nvm/v0.33.8/install.sh -o install_nvm.sh"
# ssh -i "$pkey" ubuntu@$dns_name -t "bash install_nvm.sh"
# ssh -i "$pkey" ubuntu@$dns_name -t "nvm install --lts && nvm use --lts"

# Setup the requisite build chain for mmai
ssh -i "$pkey" ubuntu@$dns_name -t "
    # Install GitHub CLI and authenticate
    sudo snap install gh &&
    gh auth login --with-token < /home/ubuntu/ghtoken &&
    
    # Install Go
    wget https://go.dev/dl/go1.23.2.linux-amd64.tar.gz &&
    sudo rm -rf /usr/local/go &&
    sudo tar -C /usr/local -xzf go1.23.2.linux-amd64.tar.gz &&
    echo 'export PATH=\$PATH:/usr/local/go/bin' >> ~/.bashrc &&
    
    # Install Docker stack
    sudo snap install docker &&
    
    # Install build tools
    curl -sL https://raw.githubusercontent.com/creationix/nvm/v0.33.8/install.sh -o install_nvm.sh &&
    bash install_nvm.sh &&
    source ~/.bashrc &&
    nvm install --lts &&
    nvm use --lts
"

echo "You may now connect to the instance via `ssh -i $pkey ubuntu@$dns_name`."