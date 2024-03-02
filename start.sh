#!/bin/bash
## install terraform
git clone https://github.com/tfutils/tfenv.git ~/.tfenv
mkdir ~/bin
ln -s ~/.tfenv/bin/* ~/bin/
tfenv install 1.2.5
tfenv use 1.2.5

user=$(aws sts get-caller-identity --query Arn --output text | cut -d '/' -f 2))
sed -i "s/CUSTOM-USERNAME/$user/" terraform/nodes.tf 

git clone https://github.com/guragainroshan0/certified-kubernetes-administrator-course

cd certified-kubernetes-administrator-course/managed-clusters/eks
terraform init
terraform plan
terraform apply -auto-approve


# create kubeconfig
aws eks update-kubeconfig --region eu-west-1 --name demo-eks

# add node as worker node
curl -O https://s3.us-west-2.amazonaws.com/amazon-eks/cloudformation/2020-10-29/aws-auth-cm.yaml
sed -i "s/<.*>/arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role\/eks-demo-node/" aws-auth-cm.yaml
kubectl apply -f aws-auth-cm.yaml


# attach policy arn
aws iam attach-role-policy --role-name eks-demo-node --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
oidc=$(aws eks describe-cluster --name demo-eks --query cluster.identity.oidc.issuer --output text | sed 's/https:\/\///g')
cat <<EOF > trust-policy.json
{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": {
          "Federated": "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):oidc-provider/$oidc"
        },
        "Action": "sts:AssumeRoleWithWebIdentity",
        "Condition": {
          "StringEquals": {
            "$oidc:aud": "sts.amazonaws.com",
            "$oidc:sub": "system:serviceaccount:kube-system:ebs-csi-controller-sa"
          }
        }
      }
    ]
  }
EOF

aws iam create-role --role-name AmazonEKS_EBS_CSI_Driver --assume-role-policy-document file://"trust-policy.json"
aws iam attach-role-policy --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy --role-name AmazonEKS_EBS_CSI_Driver

