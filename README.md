# Parking Ticket System (AWS Lambda + RDS + Terraform)

This project provisions a serverless parking ticket system using:

- AWS Lambda (2 functions)
- RDS MySQL (for storage)
- API Gateway (HTTP API)
- Terraform (automation and infrastructure as code)
- NAT Gateway for internet access
- Lambda Layers for shared code and pymysql dependency

---

## Features

- `POST /entry`: Accepts a license plate and parking lot, generates a UUID ticket and stores it.
- `POST /exit`: Accepts a ticket ID and calculates parking duration and cost.
- Uses RDS MySQL to persist ticket data.
- Deployed entirely through Terraform.

---

## How to run

### 1. Prerequisites

- Terraform CLI installed
- AWS credentials configured (`~/.aws/credentials` or env vars)
- Python installed

### 2. Run terraform automation
- `cd terraform`
- `terraform init`
- `terraform apply`

---

## API Endpoints:
Get created url with this command after creation: `terraform output api_url`  

### Entry API:
```commandline
curl -X POST "<API_URL>/entry?plate=123-ABC&parkingLot=LotA" 
```

### Exit API:
```commandline
curl -X POST "<API_URL>/exit?ticketId=uuid-string" 

```

---

## Tear Down Resources
To destroy all AWS resources:
```commandline
terraform destroy
```
