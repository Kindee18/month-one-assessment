# TechCorp Web Application Infrastructure

This repository contains Terraform configurations to deploy a highly available web application infrastructure on AWS for TechCorp.

## Architecture Overview

The infrastructure includes:

- VPC with public and private subnets across 2 availability zones
- Internet Gateway and NAT Gateways for internet connectivity
- Application Load Balancer for high availability
- Bastion host for secure administrative access
- Web servers in private subnets
- Database server in private subnet
- Appropriate security groups and routing

## Prerequisites

Before deploying this infrastructure, ensure you have:

1. **AWS CLI configured** with appropriate credentials

   ```bash
   aws configure
   ```

2. **Terraform installed** (version 1.0 or later)

   ```bash
   # On macOS
   brew install terraform

   # On Linux
   wget https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
   unzip terraform_1.6.0_linux_amd64.zip
   sudo mv terraform /usr/local/bin/

   # On windows
   choco install terraform
   ```

3. **SSH Key Pair** generated

   ```bash
   ssh-keygen -t rsa -b 2048 -f ~/.ssh/id_rsa
   ```

4. **Your current IP address** for bastion host access
   ```bash
   curl ifconfig.me
   ```

## File Structure

```
terraform-assessment/
├── main.tf                    # Main Terraform configuration
├── variables.tf               # Variable declarations
├── outputs.tf                 # Output definitions
├── terraform.tfvars.example   # Example variable values
├── user_data/
│   ├── web_server_setup.sh    # Web server configuration script
│   └── db_server_setup.sh     # Database server configuration script
├── evidence/                  # Deployment screenshots
└── README.md                  # This file
```

## Local setup script

If present, the `setup.sh` script provides a small local automation helper that:

- Generates an SSH key if one is not found locally
- Detects your public IP and inserts it into `terraform.tfvars`
- Reminds you to run `terraform init`, `terraform plan`, and `terraform apply`

This kind of scripting demonstrates useful automation skills — writing idempotent, repeatable setup steps is a good cloud engineering practice. For safety in public repos we recommend keeping a tracked template (for example `setup.example.sh`) and adding `setup.sh` to `.gitignore` so users run and customize the script locally rather than committing generated secrets or keys. See the "Sanitizing evidence and exported state" section for guidance on what to avoid committing.

## Deployment Instructions

### Step 1: Clone and Configure

1. Clone this repository:

   ```bash
   git clone <repository-url>
   cd month-one-assessment
   ```

2. Copy the example variables file:

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

3. Edit `terraform.tfvars` with your specific values:

   ```bash
   nano terraform.tfvars
   ```

   Update the following variables:

   - `my_ip`: Your current IP address (e.g., "203.0.113.1/32")
   - `aws_region`: Your preferred AWS region
   - `public_key_path`: Path to your SSH public key
   - `server_password`: Secure password for server access (do NOT commit secrets; set locally)

### Step 2: Initialize Terraform

```bash
terraform init
```

### Step 3: Plan the Deployment

```bash
terraform plan
```

Review the planned changes to ensure everything looks correct.

### Step 4: Deploy the Infrastructure

```bash
terraform apply
```

Type `yes` when prompted to confirm the deployment.

### Step 5: Verify Deployment

After successful deployment, note the outputs:

- VPC ID
- Load Balancer DNS name
- Bastion public IP

## ASG / Auto Scaling Group and outputs

- The web tier is managed by an Auto Scaling Group (ASG) using a Launch Template. The ASG will create EC2 instances after Terraform completes the resource provisioning. Because of this timing, outputs that look up web instance private IPs via a data source (tag lookup) may be empty immediately after the first `terraform apply`.

- Recommended workflow to obtain web instance private IPs (two-step):
  1.  Run `terraform apply` to create the ASG, ALB, and supporting infrastructure.
  2.  After the apply finishes, refresh Terraform's view of the world so the data source can discover ASG-launched instances:

```bash
terraform refresh
# or re-run apply which also refreshes state
terraform apply
```

- Once refreshed, the `web_server_private_ips` output (provided by the configuration) will be populated. This behaviour is documented in `outputs.tf`.

### Viewing CloudWatch metrics in the AWS Console

If you want to inspect autoscaling, ALB, or EC2 metrics without provisioning additional CloudWatch resources, use the AWS Console:

- Open the CloudWatch console: https://console.aws.amazon.com/cloudwatch/
- Metrics → All metrics

- For the Application Load Balancer (ALB): select **`AWS/ApplicationELB`** and choose the Load Balancer or Target Group to view metrics such as `RequestCountPerTarget`, `TargetResponseTime`, and `HealthyHostCount`.
- For Auto Scaling Group metrics: select **`AWS/AutoScaling`** and pick your Auto Scaling Group (look for `techcorp-web-asg`) to see `GroupDesiredCapacity`, `GroupInServiceInstances`, etc.
- For EC2 (instance) metrics such as CPU: select **`AWS/EC2`** → By AutoScalingGroupName or InstanceId and view `CPUUtilization`.

Quick CLI checks (useful during testing):

```bash
# ASG activity
aws autoscaling describe-scaling-activities --auto-scaling-group-name techcorp-web-asg

# ALB target health (replace with actual target group arn if needed)
aws elbv2 describe-target-health --target-group-arn $(terraform output -raw web_tg_arn)

# Inspect an EC2 metric via CloudWatch (example: CPU utilization for an instance)
aws cloudwatch get-metric-statistics --namespace AWS/EC2 --metric-name CPUUtilization \
   --start-time $(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%SZ) \
   --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) --period 60 --statistics Average \
   --dimensions Name=InstanceId,Value=<instance-id>
```

These views let you monitor scaling behavior and ALB health without adding additional CloudWatch resources. If you later want alerts or log collection, we can add low-cost CloudWatch alarms and log groups.

### ASG tuning: cooldown, warmup and scaling

- This deployment configures the web tier ASG to start with two instances and allows scaling up (see `min_size`, `desired_capacity`, `max_size` in `main.tf`). To avoid rapid re-scaling while new instances boot and register with the ALB, the ASG is configured with the following conservative defaults:

  - `default_cooldown = 180` seconds — the ASG waits this period after a scaling activity before allowing another action
  - `health_check_grace_period = 180` seconds — gives new instances time to start services and pass ALB health checks before being considered unhealthy

- These values reduce "flapping" and are safe defaults for Amazon Linux + typical web app startup tasks. If your instances boot faster you can shorten them.

- Scaling policy:

  - A Target-Tracking scaling policy is configured to track `ASGAverageCPUUtilization` with a target value (see `main.tf`). This automatically scales the ASG to keep average CPU near the configured target.
  - For HTTP workloads behind an ALB you may prefer `ALBRequestCountPerTarget` (RequestCountPerTarget) as a scaling metric — it scales based on requests per target and is often a better proxy for HTTP load. This requires adding a target-tracking policy that references the ALB/target-group resource label and tuning the `target_value` after load testing.

- Testing scaling behaviour:
  1. Run `terraform apply` to create the ASG and ALB.

2. Generate load against the ALB (e.g., `ab` or `wrk`) and monitor ASG Activity and CloudWatch metrics:

```bash
# generate load (example)
ab -n 10000 -c 50 http://$(terraform output -raw load_balancer_dns_name)/

# monitor ASG activity
aws autoscaling describe-scaling-activities --auto-scaling-group-name techcorp-web-asg

# check ALB target health
aws elbv2 describe-target-health --target-group-arn $(terraform output -raw web_tg_arn)
```

3.  After load drops, the ASG will scale-in automatically (respecting cooldown/grace settings).

## Access Instructions

### Accessing the Web Application

1. **Via Load Balancer**: Use the Load Balancer DNS name from the Terraform output
   ```
   http://<load-balancer-dns-name>
   ```

### Accessing Servers via Bastion Host

1. **Connect to Bastion Host**:

   ```bash
   ssh -i ~/.ssh/id_rsa ec2-user@<bastion-public-ip>
   ```

2. **From Bastion to Web Servers**:

   ```bash
   # Using SSH key (recommended)
   ssh -i ~/.ssh/id_rsa ec2-user@<web-server-private-ip>

   # Using username/password (for demonstration only)
   # The `techcorp` user password is set from the `server_password` variable.
   # Do not store plaintext passwords in version control; set `server_password`
   # in your local `terraform.tfvars` or via environment variables.
   ssh techcorp@<web-server-private-ip>
   ```

3. **From Bastion to Database Server**:

   ```bash
   # Using SSH key (recommended)
   ssh -i ~/.ssh/id_rsa ec2-user@<db-server-private-ip>

   # Using username/password (for demonstration only)
   # The `techcorp` user password is set from the `server_password` variable.
   ssh techcorp@<db-server-private-ip>
   ```

### Accessing PostgreSQL Database

1. **Connect to Database Server** (via bastion):

   ```bash
   ssh techcorp@<db-server-private-ip>
   ```

2. **Connect to PostgreSQL**:

   ```bash
   sudo -u postgres psql -d techcorp_db
   ```

3. **Test the database**:
   ```sql
   SELECT * FROM test_table;
   \q
   ```

### Security Configuration

### Security Groups

- **Bastion Security Group**: SSH (22) from your IP only
- **ALB Security Group**: HTTP (80) and HTTPS (443) from the internet (0.0.0.0/0)
- **Web Security Group**: Accepts HTTP/HTTPS only from the ALB security group; SSH (22) from bastion
- **Database Security Group**: The DB server runs **PostgreSQL (5432)** (installed by the user-data script) and the SG allows 5432 from the web servers. The configuration also includes a network ingress rule for **MySQL (3306)** from the web SG to satisfy the original SG requirement — this permits MySQL traffic at the network layer but MySQL is not installed by default. If you prefer strict Postgres-only configuration we can remove the 3306 rule, or convert the DB server to MySQL on request.

### Network Configuration

- **Public Subnets**: 10.0.1.0/24, 10.0.2.0/24
- **Private Subnets**: 10.0.3.0/24, 10.0.4.0/24
- **VPC CIDR**: 10.0.0.0/16

## Troubleshooting

### Common Issues

1. **SSH Connection Refused**:

   - Ensure your IP is correctly set in `terraform.tfvars`
   - Check security group rules
   - Verify the bastion host is running

2. **Web Application Not Loading**:

   - Check if instances are healthy in the target group
   - Verify security group allows HTTP traffic
   - Ensure Apache is running on web servers

3. **Database Connection Issues**:
   - Verify PostgreSQL is running: `systemctl status postgresql`
   - Check firewall rules: `firewall-cmd --list-all`
   - Ensure database is accepting connections

### Useful Commands

```bash
# Check Terraform state
terraform show

# Get specific output
terraform output load_balancer_dns_name

# Refresh state
terraform refresh

# Check instance status
aws ec2 describe-instances --filters "Name=tag:Name,Values=techcorp-*"
```

## Cleanup Instructions

To destroy the infrastructure and avoid ongoing charges:

```bash
terraform destroy
```

Type `yes` when prompted to confirm the destruction.

**Warning**: This will permanently delete all resources. Ensure you have backed up any important data.

## Remote Terraform State (recommended)

When collaborating, avoid committing Terraform state files to source control. State files can contain sensitive information (resource IDs, IPs, etc.). Instead, use a remote backend such as AWS S3 with state locking via DynamoDB.

Example S3 backend block (add to `main.tf` and configure the S3 bucket/DynamoDB table first):

```hcl
terraform {
   backend "s3" {
      bucket         = "my-terraform-state-bucket"
      key            = "month-one-assessment/terraform.tfstate"
      region         = "us-east-1"
      dynamodb_table = "terraform-locks"
      encrypt        = true
   }
}
```

If a local `terraform.tfstate` file has already been committed, remove it from Git history and your working tree:

```bash
# Remove local state from repo and stop tracking
git rm --cached terraform.tfstate terraform.tfstate.backup
git commit -m "Remove terraform state files from repo"

# Optionally purge from history (use with caution)
# git filter-branch --force --index-filter 'git rm --cached --ignore-unmatch terraform.tfstate' --prune-empty --tag-name-filter cat -- --all
```

After configuring the backend, run:

```bash
terraform init
terraform apply
```

Note: Do not change or migrate backends for existing real deployments without first ensuring you have proper access to the existing state.

## Sanitizing evidence and exported state

Before you submit this repository or share any exported state or screenshots, review the `evidence/` folder and any local `terraform.tfstate` files for sensitive information. Redact or remove items such as:

- Plaintext passwords, API keys, or secrets
- Private SSH keys or private portions of key pairs
- Full IP addresses that must remain private for the submission

If you previously committed `terraform.tfstate`, remove it from the repository and from history (see Remote Terraform State section) and ensure you don't include `terraform.tfvars` with secrets. Sanitize screenshots in `evidence/` to remove any leaked values.

## Cost Considerations

This infrastructure uses the following AWS resources:

- 4 EC2 instances (1 t3.micro bastion, 2 t3.micro web servers, 1 t3.small database)
- 1 Application Load Balancer
- 2 NAT Gateways
- 3 Elastic IPs
- VPC and associated networking components

Estimated monthly cost: $50-80 USD (varies by region and usage)

## Support

For issues or questions:

1. Check the troubleshooting section above
2. Review AWS CloudFormation events in the AWS Console
3. Check Terraform logs for detailed error messages
4. Verify AWS credentials and permissions

## Security Best Practices Implemented

- Private subnets for application and database tiers
- Bastion host for secure administrative access
- Security groups with least privilege access
- NAT Gateways for outbound internet access from private subnets
- Separate security groups for each tier
- Password authentication configured for demonstration (SSH keys recommended for production)
