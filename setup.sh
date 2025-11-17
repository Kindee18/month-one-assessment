#!/bin/bash

echo "TechCorp Infrastructure Setup Script"
echo "===================================="

# Check if SSH key exists
if [ ! -f ~/.ssh/id_rsa ]; then
    echo "SSH key not found. Generating new SSH key pair..."
    ssh-keygen -t rsa -b 2048 -f ~/.ssh/id_rsa -N ""
    echo "SSH key generated successfully!"
else
    echo "SSH key already exists at ~/.ssh/id_rsa"
fi

# Get current IP address
echo "Getting your current IP address..."
CURRENT_IP=$(curl -s ifconfig.me)
echo "Your current IP address is: $CURRENT_IP"

# Create terraform.tfvars if it doesn't exist
if [ ! -f terraform.tfvars ]; then
    echo "Creating terraform.tfvars file..."
    cp terraform.tfvars.example terraform.tfvars
    
    # Update the IP address in terraform.tfvars
    sed -i "s/YOUR_IP_ADDRESS/$CURRENT_IP/" terraform.tfvars
    
    echo "terraform.tfvars created with your IP address: $CURRENT_IP/32"
    echo "Please review and update terraform.tfvars with any other required changes."
else
    echo "terraform.tfvars already exists. Please update manually if needed."
fi

echo ""
echo "Setup complete! Next steps:"
echo "1. Review and update terraform.tfvars if needed"
echo "2. Run 'terraform init' to initialize Terraform"
echo "3. Run 'terraform plan' to review the deployment plan"
echo "4. Run 'terraform apply' to deploy the infrastructure"