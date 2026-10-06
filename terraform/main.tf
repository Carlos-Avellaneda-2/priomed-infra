# Esqueleto de la Figura 3 (plan de despliegue AWS). NO VALIDADO: terraform no estaba disponible
# al generarlo. Corre `terraform init && terraform validate` antes de usarlo.
# Para AWS Academy Learner Lab: no puedes crear roles IAM; usa el LabRole existente y revisa
# que servicios están permitidos (SQS/ElastiCache pueden estar restringidos).
terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

data "aws_availability_zones" "available" {
  state = "available"
}

# ---------- Red: VPC, subred pública (ALB) y subredes privadas (cómputo / datos) ----------
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags                 = { Name = "${var.name}-vpc" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.name}-public-${count.index}" }
}

resource "aws_subnet" "private_compute" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, 10 + count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags              = { Name = "${var.name}-private-compute-${count.index}" }
}

resource "aws_subnet" "private_data" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, 20 + count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags              = { Name = "${var.name}-private-data-${count.index}" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ---------- Grupos de seguridad ----------
resource "aws_security_group" "alb" {
  name   = "${var.name}-alb"
  vpc_id = aws_vpc.main.id
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "compute" {
  name   = "${var.name}-compute"
  vpc_id = aws_vpc.main.id
  ingress {
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "data" {
  name   = "${var.name}-data"
  vpc_id = aws_vpc.main.id
  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.compute.id]
  }
}

# ---------- Datos: PostgreSQL (RDS) ----------
resource "aws_db_subnet_group" "data" {
  name       = "${var.name}-data"
  subnet_ids = aws_subnet.private_data[*].id
}

resource "aws_db_instance" "postgres" {
  identifier             = "${var.name}-db"
  engine                 = "postgres"
  engine_version         = "16"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  db_name                = "priomed"
  username               = "priomed"
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.data.name
  vpc_security_group_ids = [aws_security_group.data.id]
  storage_encrypted      = true
  multi_az               = false # configuración reducida del prototipo (Sección 7.3)
  skip_final_snapshot    = true
}

# ---------- Servicios gestionados: S3, SQS, Secrets Manager ----------
resource "aws_s3_bucket" "referrals" {
  bucket_prefix = "${var.name}-referrals-"
}

resource "aws_s3_bucket_public_access_block" "referrals" {
  bucket                  = aws_s3_bucket.referrals.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "referrals" {
  bucket = aws_s3_bucket.referrals.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_sqs_queue" "classification_dlq" {
  name = "${var.name}-classification-dlq"
}

resource "aws_sqs_queue" "classification" {
  name = "${var.name}-classification"
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.classification_dlq.arn
    maxReceiveCount     = 5
  })
}

resource "aws_secretsmanager_secret" "llm" {
  name_prefix = "${var.name}/llm-credentials-"
}
