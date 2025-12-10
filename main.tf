terraform {
  required_version = ">= 1.6.0"

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

########################
# Caller Identity      #
########################

data "aws_caller_identity" "current" {}

########################
# Kinesis Data Stream  #
########################

resource "aws_kinesis_stream" "votes_stream" {
  name        = "${var.project_name}-stream"
  shard_count = 1

  # optional; defaults are fine for a lab
  retention_period = 24
}

########################
# DynamoDB Tables      #
########################

# Table 1: votes (one row per user vote)
resource "aws_dynamodb_table" "votes" {
  name         = "${var.project_name}-votes"
  billing_mode = "PAY_PER_REQUEST"

  hash_key = "userId"

  attribute {
    name = "userId"
    type = "S"
  }
}

# Table 2: intermediate results (per poll/option counts)
resource "aws_dynamodb_table" "intermediate_results" {
  name         = "${var.project_name}-intermediate-results"
  billing_mode = "PAY_PER_REQUEST"

  hash_key  = "pollId"
  range_key = "option"

  attribute {
    name = "pollId"
    type = "S"
  }

  attribute {
    name = "option"
    type = "S"
  }
}

########################
# IAM for Lambda       #
########################

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_role" {
  name               = "${var.project_name}-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

data "aws_iam_policy_document" "lambda_policy_doc" {
  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]

    resources = ["*"]
  }

  statement {
    sid    = "DynamoAccess"
    effect = "Allow"

    actions = [
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:GetItem",
      "dynamodb:Query",
      "dynamodb:DescribeTable"
    ]

    resources = [
      aws_dynamodb_table.votes.arn,
      aws_dynamodb_table.intermediate_results.arn
    ]
  }

  statement {
    sid    = "KinesisRead"
    effect = "Allow"

    actions = [
      "kinesis:GetRecords",
      "kinesis:GetShardIterator",
      "kinesis:DescribeStream",
      "kinesis:DescribeStreamSummary",
      "kinesis:ListShards",
      "kinesis:ListStreams"
    ]

    resources = [
      aws_kinesis_stream.votes_stream.arn
    ]
  }
}

resource "aws_iam_policy" "lambda_policy" {
  name   = "${var.project_name}-lambda-policy"
  policy = data.aws_iam_policy_document.lambda_policy_doc.json
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

########################
# Lambda Functions     #
########################

# Python Lambda: dedupe vote (one vote per user)
resource "aws_lambda_function" "dedupe_vote" {
  function_name = "${var.project_name}-dedupe-vote"
  role          = aws_iam_role.lambda_role.arn

  runtime = "python3.12"
  handler = "dedupe_vote.lambda_handler"

  filename         = "${path.module}/lambda/dedupe_vote.zip"
  source_code_hash = filebase64sha256("${path.module}/lambda/dedupe_vote.zip")

  environment {
    variables = {
      VOTES_TABLE_NAME = aws_dynamodb_table.votes.name
    }
  }
}

# Python Lambda: aggregate results (every vote counted)
resource "aws_lambda_function" "aggregate_results" {
  function_name = "${var.project_name}-aggregate-results"
  role          = aws_iam_role.lambda_role.arn

  runtime = "python3.12"
  handler = "aggregate_results.lambda_handler"

  filename         = "${path.module}/lambda/aggregate_results.zip"
  source_code_hash = filebase64sha256("${path.module}/lambda/aggregate_results.zip")

  environment {
    variables = {
      INTERMEDIATE_TABLE_NAME = aws_dynamodb_table.intermediate_results.name
    }
  }
}

# Results Lambda: reads intermediate_results table and returns JSON summary
resource "aws_lambda_function" "results" {
  function_name = "${var.project_name}-results"
  role          = aws_iam_role.lambda_role.arn

  runtime = "python3.12"
  handler = "results.lambda_handler"

  filename         = "${path.module}/lambda/results.zip"
  source_code_hash = filebase64sha256("${path.module}/lambda/results.zip")

  environment {
    variables = {
      INTERMEDIATE_TABLE_NAME = aws_dynamodb_table.intermediate_results.name
    }
  }
}

########################
# Kinesis → Lambda     #
########################

# Lambda 1: consumes stream to enforce 1 vote per user → writes to votes table
resource "aws_lambda_event_source_mapping" "dedupe_mapping" {
  event_source_arn  = aws_kinesis_stream.votes_stream.arn
  function_name     = aws_lambda_function.dedupe_vote.arn
  starting_position = "LATEST"
  batch_size        = 100
  enabled           = true
}

# Lambda 2: consumes same stream, counts every vote → writes to intermediate_results
resource "aws_lambda_event_source_mapping" "aggregate_mapping" {
  event_source_arn  = aws_kinesis_stream.votes_stream.arn
  function_name     = aws_lambda_function.aggregate_results.arn
  starting_position = "LATEST"
  batch_size        = 100
  enabled           = true
}

########################
# IAM for API → Kinesis #
########################

data "aws_iam_policy_document" "apigw_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["apigateway.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "apigw_role" {
  name               = "${var.project_name}-apigw-kinesis-role"
  assume_role_policy = data.aws_iam_policy_document.apigw_assume_role.json
}

data "aws_iam_policy_document" "apigw_kinesis_policy_doc" {
  statement {
    effect = "Allow"

    actions = [
      "kinesis:PutRecord",
      "kinesis:PutRecords"
    ]

    resources = [aws_kinesis_stream.votes_stream.arn]
  }
}

resource "aws_iam_policy" "apigw_kinesis_policy" {
  name   = "${var.project_name}-apigw-kinesis-policy"
  policy = data.aws_iam_policy_document.apigw_kinesis_policy_doc.json
}

resource "aws_iam_role_policy_attachment" "apigw_kinesis_policy_attach" {
  role       = aws_iam_role.apigw_role.name
  policy_arn = aws_iam_policy.apigw_kinesis_policy.arn
}

########################
# API Gateway (REST)   #
########################

resource "aws_api_gateway_rest_api" "votes_api" {
  name        = "${var.project_name}-api"
  description = "Real-time voting API -> Kinesis -> Lambdas -> DynamoDB"
}

# /vote resource
resource "aws_api_gateway_resource" "vote_resource" {
  rest_api_id = aws_api_gateway_rest_api.votes_api.id
  parent_id   = aws_api_gateway_rest_api.votes_api.root_resource_id
  path_part   = "vote"
}

# POST /vote
resource "aws_api_gateway_method" "post_vote" {
  rest_api_id   = aws_api_gateway_rest_api.votes_api.id
  resource_id   = aws_api_gateway_resource.vote_resource.id
  http_method   = "POST"
  authorization = "NONE"
}

# /results resource
resource "aws_api_gateway_resource" "results_resource" {
  rest_api_id = aws_api_gateway_rest_api.votes_api.id
  parent_id   = aws_api_gateway_rest_api.votes_api.root_resource_id
  path_part   = "results"
}

# GET /results
resource "aws_api_gateway_method" "get_results" {
  rest_api_id   = aws_api_gateway_rest_api.votes_api.id
  resource_id   = aws_api_gateway_resource.results_resource.id
  http_method   = "GET"
  authorization = "NONE"
}

# Integration: API Gateway → Kinesis service proxy (no Lambda in the middle)
resource "aws_api_gateway_integration" "post_vote_integration" {
  rest_api_id = aws_api_gateway_rest_api.votes_api.id
  resource_id = aws_api_gateway_resource.vote_resource.id
  http_method = aws_api_gateway_method.post_vote.http_method

  type                    = "AWS"
  integration_http_method = "POST"
  uri                     = "arn:aws:apigateway:${var.region}:kinesis:action/PutRecord"
  credentials             = aws_iam_role.apigw_role.arn

  request_templates = {
    "application/json" = <<EOF
{
  "StreamName": "${aws_kinesis_stream.votes_stream.name}",
  "PartitionKey": "$context.requestId",
  "Data": "$util.base64Encode($input.body)"
}
EOF
  }

  passthrough_behavior = "NEVER"
}

# Method/Integration responses (minimal, 200 OK only)
resource "aws_api_gateway_method_response" "post_vote_200" {
  rest_api_id = aws_api_gateway_rest_api.votes_api.id
  resource_id = aws_api_gateway_resource.vote_resource.id
  http_method = aws_api_gateway_method.post_vote.http_method
  status_code = "200"
}

resource "aws_api_gateway_integration_response" "post_vote_integration_200" {
  rest_api_id = aws_api_gateway_rest_api.votes_api.id
  resource_id = aws_api_gateway_resource.vote_resource.id
  http_method = aws_api_gateway_method.post_vote.http_method
  status_code = aws_api_gateway_method_response.post_vote_200.status_code

  # Simple "pass-through" response body; Kinesis response is ignored
  response_templates = {
    "application/json" = ""
  }

  depends_on = [
    aws_api_gateway_integration.post_vote_integration
  ]
}

# Integration: API Gateway → Results Lambda (proxy)
resource "aws_api_gateway_integration" "get_results_integration" {
  rest_api_id = aws_api_gateway_rest_api.votes_api.id
  resource_id = aws_api_gateway_resource.results_resource.id
  http_method = aws_api_gateway_method.get_results.http_method

  type                    = "AWS_PROXY"
  integration_http_method = "POST"
  uri                     = "arn:aws:apigateway:${var.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.results.arn}/invocations"
}

# Allow API Gateway to invoke the Results Lambda
resource "aws_lambda_permission" "apigw_invoke_results" {
  statement_id  = "AllowAPIGatewayInvokeResults"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.results.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "arn:aws:execute-api:${var.region}:${data.aws_caller_identity.current.account_id}:${aws_api_gateway_rest_api.votes_api.id}/*/${aws_api_gateway_method.get_results.http_method}${aws_api_gateway_resource.results_resource.path}"
}

########################
# Deployment + Stage   #
########################

resource "aws_api_gateway_deployment" "votes_deployment" {
  rest_api_id = aws_api_gateway_rest_api.votes_api.id

  # Force new deployment when key resources change
  triggers = {
    redeployment = sha1(jsonencode({
      vote_resource_id            = aws_api_gateway_resource.vote_resource.id
      post_vote_method_id         = aws_api_gateway_method.post_vote.id
      post_vote_integration_id    = aws_api_gateway_integration.post_vote_integration.id
      results_resource_id         = aws_api_gateway_resource.results_resource.id
      get_results_method_id       = aws_api_gateway_method.get_results.id
      get_results_integration_id  = aws_api_gateway_integration.get_results_integration.id
    }))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_integration.post_vote_integration,
    aws_api_gateway_integration.get_results_integration
  ]
}

resource "aws_api_gateway_stage" "prod" {
  rest_api_id   = aws_api_gateway_rest_api.votes_api.id
  deployment_id = aws_api_gateway_deployment.votes_deployment.id
  stage_name    = "prod"
}