

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
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = "true"
}

# SUBNET
resource "aws_subnet" "terraform_subnet" {
  cidr_block              = var.subnet1_cidr
  vpc_id                  = aws_vpc.terraform_vpc.id
  map_public_ip_on_launch = "true"
  availability_zone       = data.aws_availability_zones.available.names[1]
}


# INTERNET_GATEWAY
resource "aws_internet_gateway" "terraform_gateway" {
  vpc_id = aws_vpc.terraform_vpc.id
}

# ROUTE_TABLE
resource "aws_route_table" "terraform_route_table" {
  vpc_id = aws_vpc.terraform_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.terraform_gateway.id
  }
}

resource "aws_route_table_association" "terraform_route_subnet" {
  subnet_id = aws_subnet.terraform_subnet.id
  route_table_id = aws_route_table.terraform_route_table.id
}



# INSTANCE
resource "aws_instance" "terraform_instance" {
  count                  = 3

  ami                    = data.aws_ami.aws-linux.id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.terraform_subnet.id
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
  subnets         = aws_subnet.terraform_subnet.*.id
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
