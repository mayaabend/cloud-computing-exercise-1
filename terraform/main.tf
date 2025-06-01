# -------------------------------
# AWS Provider Configuration
# -------------------------------
provider "aws" {
  region = var.region
}

# -------------------------------
# Networking Setup
# -------------------------------
# Create the main VPC
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

# Create two public subnets for NAT Gateway and potential public use
resource "aws_subnet" "public" {
  count = 2
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.${count.index}.0/24"
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
  map_public_ip_on_launch = true

  tags = {
    Name = "public-${count.index}"
  }
}

# Create two private subnets for Lambda and RDS
resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.${count.index + 100}.0/24"
  availability_zone = element(data.aws_availability_zones.available.names, count.index)

  tags = {
    Name = "private-${count.index}"
  }
}

# Fetch available AZs dynamically
data "aws_availability_zones" "available" {}

# Set up Internet Gateway for public subnets
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

# Allocate EIP and NAT Gateway for private subnets to access the internet
resource "aws_eip" "nat_eip" {
  vpc = true
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public[0].id
  depends_on    = [aws_internet_gateway.igw]
}

# Public and private route tables and associations
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "public-rt"
  }
}

resource "aws_route_table_association" "public_rt_assoc" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name = "private-rt"
  }
}

resource "aws_route_table_association" "private_rt_assoc" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private_rt.id
}

# -------------------------------
# RDS MySQL Instance
# -------------------------------
# Security group allowing Lambda to connect to RDS
resource "aws_security_group" "rds_sg" {
  name        = "rds_sg"
  description = "Allow Lambda access"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# MySQL instance creation
resource "aws_db_instance" "mysql" {
  identifier         = "parking-db"
  allocated_storage  = 20
  engine             = "mysql"
  engine_version     = "8.0"
  instance_class     = "db.t3.micro"
  db_name            = var.db_name
  username           = var.db_username
  password           = var.db_password
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name   = aws_db_subnet_group.db_subnets.name
  skip_final_snapshot    = true
}

# Subnet group for RDS to use the private subnets
resource "aws_db_subnet_group" "db_subnets" {
  name       = "db-subnet-group"
  subnet_ids = aws_subnet.private[*].id
}

# -------------------------------
# IAM Role for Lambda Execution
# -------------------------------
resource "aws_iam_role" "lambda_exec" {
  name = "lambda_exec_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_vpc_access" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# -------------------------------
# Lambda Layers (shared code + pymysql)
# -------------------------------
resource "aws_lambda_layer_version" "pymysql_layer" {
  filename   = "${path.module}/lambda/pymysql-layer.zip"
  layer_name = "pymysql"
  compatible_runtimes = ["python3.12"]
}

resource "aws_lambda_layer_version" "shared_code" {
  filename   = "${path.module}/lambda/shared/shared-layer.zip"
  layer_name = "shared_utils"
  compatible_runtimes = ["python3.12"]
}

# -------------------------------
# Lambda Functions
# -------------------------------
resource "aws_lambda_function" "insert_ticket" {
  function_name = "insert_ticket"
  filename      = "${path.module}/lambda/insert_ticket.zip"
  handler       = "insert_ticket.lambda_handler"
  runtime       = "python3.12"
  role          = aws_iam_role.lambda_exec.arn
  timeout       = 10

  environment {
    variables = {
      DB_HOST     = aws_db_instance.mysql.address
      DB_USER_NAME = var.db_username
      DB_PASSWORD  = var.db_password
      DB_NAME      = var.db_name
    }
  }

  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.rds_sg.id]
  }

  layers = [
    aws_lambda_layer_version.pymysql_layer.arn,
    aws_lambda_layer_version.shared_code.arn
  ]
}

resource "aws_lambda_function" "get_charge" {
  function_name = "get_charge"
  filename      = "${path.module}/lambda/calculate_charge.zip"
  handler       = "calculate_charge.lambda_handler"
  runtime       = "python3.12"
  role          = aws_iam_role.lambda_exec.arn
  timeout       = 10

  environment {
    variables = {
      DB_HOST     = aws_db_instance.mysql.address
      DB_USER_NAME = var.db_username
      DB_PASSWORD  = var.db_password
      DB_NAME      = var.db_name
    }
  }

  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.rds_sg.id]
  }

  layers = [
    aws_lambda_layer_version.pymysql_layer.arn,
    aws_lambda_layer_version.shared_code.arn
  ]
}

# -------------------------------
# API Gateway: HTTP API Integration
# -------------------------------
resource "aws_apigatewayv2_api" "parking_api" {
  name          = "parking-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.parking_api.id
  name        = "$default"
  auto_deploy = true
}

# API Gateway → Lambda integration (proxy mode)
resource "aws_apigatewayv2_integration" "insert_ticket_integration" {
  api_id                = aws_apigatewayv2_api.parking_api.id
  integration_type      = "AWS_PROXY"
  integration_uri       = aws_lambda_function.insert_ticket.invoke_arn
  integration_method    = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_integration" "get_charge_integration" {
  api_id                = aws_apigatewayv2_api.parking_api.id
  integration_type      = "AWS_PROXY"
  integration_uri       = aws_lambda_function.get_charge.invoke_arn
  integration_method    = "POST"
  payload_format_version = "2.0"
}

# Define routes
resource "aws_apigatewayv2_route" "insert_ticket_route" {
  api_id    = aws_apigatewayv2_api.parking_api.id
  route_key = "POST /entry"
  target    = "integrations/${aws_apigatewayv2_integration.insert_ticket_integration.id}"
}

resource "aws_apigatewayv2_route" "get_charge_route" {
  api_id    = aws_apigatewayv2_api.parking_api.id
  route_key = "POST /exit"
  target    = "integrations/${aws_apigatewayv2_integration.get_charge_integration.id}"
}

# Define routes
resource "aws_lambda_permission" "allow_api_insert_ticket" {
  statement_id  = "AllowAPIGatewayInvokeInsert"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.insert_ticket.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.parking_api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "allow_api_get_charge" {
  statement_id  = "AllowAPIGatewayInvokeCharge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_charge.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.parking_api.execution_arn}/*/*"
}

# -------------------------------
# Outputs
# -------------------------------
output "api_url" {
  value = aws_apigatewayv2_api.parking_api.api_endpoint
}
