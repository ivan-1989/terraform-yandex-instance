#!/bin/bash

# ############################
# YC Toolbox user setup script
# ############################

# Change user prompt
echo "Change user prompt"
echo 'export PS1="\[\033[38;5;245m\]\t:[\w]\[\e[0;0m\]\n\[\033[38;5;50m\]\u\[\e[0;0m\]@\[\033[38;5;48m\]\h\[\e[0;0m\] \\$ "' >> ~/.bashrc

# Helm add default repo
echo "Add default Helm repo"
helm repo add stable https://charts.helm.sh/stable

# Terraform config
echo "Configuring Terraform"
cp /usr/local/etc/terraform.rc $HOME/.terraformrc

# Docker
echo "Grant user access to the Docker"
sudo usermod -aG docker $USER

# kubectl
echo "Kubectl auto-completion"
cat << EOF >> $HOME/.bashrc
# kubectl
source <(kubectl completion bash)
alias k=kubectl
complete -o default -F __start_kubectl k
EOF

# YC CLI
VM_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)

# Test the SA presence
folder_id=$(yc compute instance get $VM_ID > /dev/null 2>&1 )
if [ $? == 0 ]
  # SA was associated with VM - configure YC via SA
  then
    echo "YC configuration via SA"
    FOLDER_ID=$(yc compute instance get $VM_ID --format=json | jq -r .folder_id )
    CLOUD_ID=$(yc resource folder get $FOLDER_ID --format=json | jq -r .cloud_id)
    yc config profile create default
    yc config set cloud-id $CLOUD_ID
    yc config set folder-id $FOLDER_ID
    unset CLOUD_ID FOLDER_ID VM_ID

  # SA was not found - configure YC from the scratch
  else
    echo "YC configuration via Init"
    yc init
fi

# Save YC params
echo "Save YC params to the ~/.bashrc"
cat << EOF >> $HOME/.bashrc
# YC config
export YC_CLOUD_ID=$(yc config get cloud-id)
export YC_FOLDER_ID=$(yc config get folder-id)
export YC_TOKEN=\$(yc iam create-token)
export TF_VAR_CLOUD_ID=$\{YC_CLOUD_ID\}
export TF_VAR_FOLDER_ID=$\{YC_FOLDER_ID\}
export TF_VAR_SSH_PATH="~/.ssh/"
EOF

sudo sudo hostnamectl set-hostname $HOSTNAME
sudo sed -i '/127.0.1.1/s/$/ $HOSTNAME/' /etc/hosts
sudo usermod -aG docker $USER

mkdir -p ~/.postgresql && \
wget "https://storage.yandexcloud.net/cloud-certs/CA.pem" \
    --output-document ~/.postgresql/root.crt && \
chmod 0600 ~/.postgresql/root.crt

######### Update and installing a packages 
sudo apt-get update
sudo apt-get install -y nginx software-properties-common
sudo add-apt-repository ppa:certbot/certbot -y
sudo apt-get update
sudo apt install --yes postgresql-client
sudo apt-get install -y certbot python3-certbot-nginx


############ Install clickhouse-client

sudo mkdir --parents /usr/local/share/ca-certificates/Yandex && \
sudo wget "https://storage.yandexcloud.net/cloud-certs/RootCA.pem" \
   --output-document /usr/local/share/ca-certificates/Yandex/RootCA.crt && \
sudo wget "https://storage.yandexcloud.net/cloud-certs/IntermediateCA.pem" \
   --output-document /usr/local/share/ca-certificates/Yandex/IntermediateCA.crt && \
sudo chmod 655 \
   /usr/local/share/ca-certificates/Yandex/RootCA.crt \
   /usr/local/share/ca-certificates/Yandex/IntermediateCA.crt && \
sudo update-ca-certificates

echo "Adding DEB-repos"

sudo apt update && sudo apt install --yes --allow-unauthenticated apt-transport-https ca-certificates dirmngr 

sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 8919F6BD2B48D754 

echo "deb [trusted=yes] https://packages.clickhouse.com/deb stable main" | sudo tee /etc/apt/sources.list.d/clickhouse.list

#cd /etc/apt && sudo cp trusted.gpg trusted.gpg.d/ && cd ~
sudo cp /etc/apt/trusted.gpg /etc/apt/trusted.gpg.d/ 



echo "Installing dependencies"

sudo apt update  
sudo apt install --yes clickhouse-client

echo "Downloading config fail for clickhouse-client"

mkdir --parents ~/.clickhouse-client && \
wget "https://storage.yandexcloud.net/doc-files/clickhouse-client.conf.example" --output-document ~/.clickhouse-client/config.xml

#### Install VS code Serever

curl -fOL https://github.com/coder/code-server/releases/download/v4.22.0/code-server_4.22.0_amd64.deb
sudo dpkg -i code-server_4.22.0_amd64.deb
sudo systemctl enable --now code-server@$USER


sudo cp nginx_default.conf /etc/nginx/sites-available/default
sudo systemctl reload nginx

sudo certbot --nginx -d code.${public_ip}.sslip.io --non-interactive --agree-tos --register-unsafely-without-email
sudo systemctl reload nginx

sed -i 's/^password: .*/password: ${VS_PASS}/' ~/.config/code-server/config.yaml
sudo systemctl restart code-server@$USER

