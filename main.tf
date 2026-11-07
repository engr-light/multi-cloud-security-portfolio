terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "eu-north-1"
}

# 1. The Map (VPC)
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "ZeroTrust-VPC-TF"
  }
}

# 2. The Storefront (Public Subnet)
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.0.0/20"
  availability_zone       = "eu-north-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "Public-Subnet-TF"
  }
}

# 3. The Vault (Private Subnet)
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.128.0/20"
  availability_zone = "eu-north-1a"

  tags = {
    Name = "Private-Subnet-TF"
  }
}

# 4. The Door (Internet Gateway)
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "ZeroTrust-IGW-TF"
  }
}

# 5. Public Route Table & Association
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "Public-RT-TF"
  }
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public_rt.id
}

# 6. The One-Way Mirror (Elastic IP & NAT Gateway)
resource "aws_eip" "nat_eip" {
  domain = "vpc"

  tags = {
    Name = "QA-NAT-EIP-TF"
  }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public.id

  tags = {
    Name = "QA-NAT-Gateway-TF"
  }

  # The NAT Gateway requires the IGW to exist first before it can route outside
  depends_on = [aws_internet_gateway.igw]
}

# 7. Private Route Table & Association
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name = "Private-RT-TF"
  }
}

resource "aws_route_table_association" "private_assoc" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private_rt.id
}


# 8. Security Group (Firewall)
resource "aws_security_group" "qa_sg" {
  name        = "QA-Worker-SG-TF"
  description = "Allow outbound traffic for QA automation"
  vpc_id      = aws_vpc.main.id

  # Outbound rules: QA worker can access the internet (via NAT) to download packages
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "QA-Worker-SG-TF"
  }
}

# 9. Dynamically fetch the latest Amazon Linux 2023 Image
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

# 10. The Compute (EC2 QA Worker)
resource "aws_instance" "qa_worker" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.micro" # Free tier eligible in eu-north-1
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.qa_sg.id]

  tags = {
    Name = "Private-QA-Worker-TF"
  }
}