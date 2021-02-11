

# //////////////////////////////
# PROVIDERS
# //////////////////////////////
provider "aws" {
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
  region     = var.region
}

# //////////////////////////////
# RESOURCES
# //////////////////////////////


# VPC
resource "aws_vpc" "terraform_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = "true"
}

# INTERNET_GATEWAY
resource "aws_internet_gateway" "terraform_gateway" {
  vpc_id = aws_vpc.terraform_vpc.id
}


# SUBNET
resource "aws_subnet" "terraform_subnet_application" {
  cidr_block              = "10.0.1.0/24"
  vpc_id                  = aws_vpc.terraform_vpc.id
  map_public_ip_on_launch = "true"
  availability_zone       = data.aws_availability_zones.available.names[1]
}

resource "aws_subnet" "terraform_subnet_firewall" {
  cidr_block              = "10.0.0.0/24"
  vpc_id                  = aws_vpc.terraform_vpc.id
  map_public_ip_on_launch = "true"
  availability_zone       = data.aws_availability_zones.available.names[1]
}

# FIREWALL


resource "aws_networkfirewall_rule_group" "terraform_firewall_group" {
  capacity = 1000
  name     = "firewallgroup"
  type     = "STATELESS"
  rule_group {
    rules_source {
      stateless_rules_and_custom_actions {
        stateless_rule {
          priority = 5
          rule_definition {
            actions = ["aws:pass"]
            match_attributes {
              source {
                address_definition = "10.0.0.0/8"
              }
              source {
                address_definition = "192.168.0.0/16"
              }
            }
          }
        }
      }
    }
  }
}

resource "aws_networkfirewall_firewall_policy" "terraform_firewall_policy" {
  name = "firewallpolicy"
  firewall_policy {
    stateless_default_actions = ["aws:pass"]
    stateless_fragment_default_actions = ["aws:drop"]
    stateless_rule_group_reference {
      priority     = 20
      resource_arn = aws_networkfirewall_rule_group.terraform_firewall_group.arn
    }
  }
}


resource "aws_networkfirewall_firewall" "terraform_network_firewall" {
  firewall_policy_arn = aws_networkfirewall_firewall_policy.terraform_firewall_policy.arn
  name                = "firewallnetwork"
  vpc_id              = aws_vpc.terraform_vpc.id
  subnet_mapping {
    subnet_id          = aws_subnet.terraform_subnet_firewall.id
  }
}


resource "aws_network_interface" "network_subnet_firewall" {
  subnet_id  = aws_subnet.terraform_subnet_firewall.id
}
resource "aws_network_interface" "network_subnet_application" { 
  subnet_id = aws_subnet.terraform_subnet_application.id
}
data "aws_network_interface" "network_firewall" { 
  id = aws_network_interface.network_subnet_firewall.id
}
data  "aws_network_interface" "network_application" { 
  id = aws_network_interface.network_subnet_application.id
}

# ROUTE_TABLE
resource "aws_route_table" "terraform_route_table_application" {
  vpc_id = aws_vpc.terraform_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    network_interface_id = data.aws_network_interface.network_application.id
    //gateway_id = aws_internet_gateway.terraform_gateway.id
  }
}

resource "aws_route_table_association" "terraform_route_association_subnet" {
  subnet_id = aws_subnet.terraform_subnet_application.id
  route_table_id = aws_route_table.terraform_route_table_application.id
}

resource "aws_route_table" "terraform_route_table_gateway" {
  vpc_id = aws_vpc.terraform_vpc.id
  route {
    cidr_block           = aws_subnet.terraform_subnet_application.cidr_block
    network_interface_id = data.aws_network_interface.network_firewall.id
  }
}
resource "aws_route_table_association" "terraform_route_association_gateway" {
  gateway_id     = aws_internet_gateway.terraform_gateway.id
  route_table_id = aws_route_table.terraform_route_table_gateway.id
}

# INSTANCE
resource "aws_instance" "terraform_instance" {
  count                  = 3

  ami                    = data.aws_ami.aws-linux.id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.terraform_subnet_application.id
  vpc_security_group_ids = [aws_security_group.terraform_security_instance.id]
  tags                   = {Environment = var.environment_list[count.index]}
  key_name               = var.ssh_key_name

  connection {
    type        = "ssh"
    host        = self.public_ip
    user        = "ec2-user"
    private_key = file(var.private_key_path)
  }
}


// Load Balancer 

resource "aws_elb" "terraform_instance" {
  name            = "terraform-elb"
  instances       = aws_instance.terraform_instance.*.id
  subnets         = aws_subnet.terraform_subnet_application.*.id
  security_groups = [aws_security_group.terraform_security_instance.id]
 

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }
}


# //////////////////////////////
# DATA
# //////////////////////////////
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "aws-linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn-ami-hvm*"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}
