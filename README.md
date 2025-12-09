# Real-Time Voting System (Serverless on AWS)

A fully serverless, event-driven real-time voting system built using:

- Amazon API Gateway  
- Amazon Kinesis Data Streams  
- AWS Lambda (Python)  
- Amazon DynamoDB  
- Terraform infrastructure as code

Users submit votes via API Gateway → votes are pushed into a Kinesis stream → two separate Lambda functions consume the stream in parallel:

- **dedupe_vote** → enforces one vote per user  
- **aggregate_results** → counts all votes and increments running totals  

You can clone this project and deploy it into your own AWS account automatically using GitHub Actions or local Terraform commands.

---

## 🧠 Architecture Overview

```text
          (POST /vote)
 Client  ------------------> API Gateway
                               |
                               V
                         Kinesis Stream
                         /            \
                        V              V
                  dedupe_vote     aggregate_results
                   (Lambda)            (Lambda)
                       |                    |
                       V                    V
                   DynamoDB            DynamoDB
                     votes       intermediate_results

## 🛠 AWS Setup (Before Deploying)

Follow these steps to give Terraform permission to build resources in your AWS account.

### 1. Create an IAM Group
In the AWS Console:
- Go to IAM → Groups
- Click **Create Group**
- Name it: `ServerlessAdmin`
- Attach the following AWS-managed policies:
  - `AWSLambda_FullAccess`
  - `AmazonDynamoDBFullAccess`
  - `AmazonKinesisFullAccess`
  - `AmazonAPIGatewayAdministrator`
  - `IAMFullAccess`   ← required to let Terraform create IAM roles/policies

Direct link:
https://console.aws.amazon.com/iam/home#/groups

---

### 2. Create a CI User
Still in IAM:
- Go to **Users**
- Click **Create user**
- User name: `github-terraform`
- Access type: **Programmatic access**

Add this user to the `ServerlessAdmin` group.

Direct link:
https://console.aws.amazon.com/iam/home#/users

---

### 3. Create an Access Key
While viewing the user:
- Go to the **Security credentials** tab
- Click **Create access key**
- Type: **Programmatic access**
- Copy your:
  - `AWS_ACCESS_KEY_ID`
  - `AWS_SECRET_ACCESS_KEY`

(You will never paste these in code—only GitHub Actions secrets.)

Direct link:
https://console.aws.amazon.com/iam/home#/security_credentials

---

### 4. Add Secrets to GitHub

In your GitHub repo:
- Go to **Settings → Secrets and variables → Actions → New repository secret**
- Create these secrets:
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY
AWS_REGION
Direct link:
https://github.com/YOUR-USERNAME/YOUR-REPO/settings/secrets/actions

---

### 5. Trigger Deployment
After secrets are added:
- Open your repo
- Go to the **Actions** tab
- Click your Terraform workflow
- Click **Run workflow**

Terraform will provision everything automatically.

---

## 🧪 Test the API
Once the workflow completes:
- Open **API Gateway**
- Locate the `prod` stage
- Copy the **Invoke URL**
- POST to `/vote` with a JSON body (see examples in this README)

Direct link:
https://console.aws.amazon.com/apigateway/home#/apis

---

## 🧹 Manual Cleanup (IMPORTANT)

This project intentionally does **not** auto-destroy resources.
You must manually delete them when finished.

### Delete these AWS resources:
| Service | Resource |
| --- | --- |
| API Gateway | REST API (prod stage) |
| Kinesis | Data Stream |
| Lambda | `dedupe_vote`, `aggregate_results` | Event Source Mappings
| DynamoDB | `realtime-voting-votes`, `realtime-voting-intermediate-results` |
| IAM Roles | Any roles starting with `realtime-voting-` |
| IAM Policies | Any policies starting with `realtime-voting-` |
| CloudWatch Logs | Optional cleanup |

---

### Helpful Console Links
- Lambda → https://console.aws.amazon.com/lambda/home
- DynamoDB → https://console.aws.amazon.com/dynamodbv2/home
- Kinesis → https://console.aws.amazon.com/kinesis/home
- API Gateway → https://console.aws.amazon.com/apigateway/home
- IAM Roles → https://console.aws.amazon.com/iam/home#/roles
- IAM Policies → https://console.aws.amazon.com/iam/home#/policies

Search for resources beginning with: realtime-voting
---

## ⚠️ Costs
These resources are usually free/low cost on small test volumes,
but **always delete when finished** to avoid unexpected charges.