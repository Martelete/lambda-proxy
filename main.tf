provider "aws" {
  region = "eu-west-1"
}

# -----------------------
# IAM Role for Lambda
# -----------------------
resource "aws_iam_role" "lambda_role" {
  name = "go-lambda-proxy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Action = "sts:AssumeRole",
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# -----------------------
# Lambda Function (Go)
# -----------------------
# module "go_lambda" {
#   source  = "terraform-aws-modules/lambda/aws"
#   version = "~> 7.0"

#   function_name = "go-lambda-proxy"
#   description   = "Go Lambda for HTTP API Proxy"
#   handler       = "bootstrap"
#   runtime       = "provided.al2023"

#   architectures = ["x86_64"]

#   # Build Go lambda locally
#   build_in_docker = false

#   # Your bootstrap zip
#   source_path = "lambda.zip"

#   publish = true

#   # CloudWatch logging enabled by default
#   attach_cloudwatch_logs_policy = true
# }


resource "aws_lambda_function" "proxy_lambda" {
  function_name = local.lambda_name
  handler       = "bootstrap"
  runtime       = "provided.al2023"
  role          = aws_iam_role.lambda_role.arn
  filename      = "lambda.zip"
}

# -----------------------
# API Gateway REST API
# -----------------------
resource "aws_api_gateway_rest_api" "api" {
  name = local.api_gateway_name
}

resource "aws_api_gateway_resource" "proxy_resource" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "go"
}

resource "aws_api_gateway_method" "any_method" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.proxy_resource.id
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "proxy_integration" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.proxy_resource.id
  http_method             = aws_api_gateway_method.any_method.http_method
  type                    = "AWS_PROXY"
  integration_http_method = "POST"
  uri                     = aws_lambda_function.proxy_lambda.invoke_arn
}

# Allow API Gateway to call Lambda
resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.proxy_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}

# Deployment
resource "aws_api_gateway_deployment" "deploy" {
  depends_on = [aws_api_gateway_integration.proxy_integration]
  rest_api_id = aws_api_gateway_rest_api.api.id
    
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "example" {
  deployment_id = aws_api_gateway_deployment.deploy.id
  rest_api_id   = aws_api_gateway_rest_api.api.id
  stage_name    = local.stage_name
}
