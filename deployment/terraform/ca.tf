terraform {
}

provider "aws" {
  profile    = "default"
  region    = "us-west-2"
}

data "aws_iam_policy_document" "lambda-assume-role" {
    statement {
        actions = ["sts:AssumeRole"]
        principals {
            type = "Service"
            identifiers = ["lambda.amazonaws.com"]
        }
    }
}
resource "aws_iam_role" "ca-role" {
    name = "ca-role"
    assume_role_policy = data.aws_iam_policy_document.lambda-assume-role.json
}
 
resource "aws_iam_role_policy_attachment" "attach-base-lambda-policy-ca" {
    role       = aws_iam_role.ca-role.name
    policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "secrets-access-policy" {
    statement {
        actions = [
            "secretsmanager:GetSecretValue"           
        ]
        resources = [
            "*", // TODO tighten up
        ]
    }
}

resource "aws_iam_policy" "secrets-access-policy" {
    name = "ca-secrets-access"
    path = "/"
    policy = data.aws_iam_policy_document.secrets-access-policy.json
}

resource "aws_iam_role_policy_attachment" "ca-sm-access" {
    role       = aws_iam_role.ca-role.name
    policy_arn = aws_iam_policy.secrets-access-policy.arn
}

resource "aws_lambda_function" "ca" {
    filename      = "lambda-ca.zip" # TODO fix this
    function_name = "epithet-ca"
    role          = aws_iam_role.ca-role.arn
    handler       = "epithet-ca-lambda"
    runtime       = "go1.x"
    source_code_hash = filebase64sha256("../../epithet-ca-lambda.zip")
    environment {
        variables = {
            PRIVKEY_SECRET_NAME = "xnio/ca-key"
        }
    }
}

resource "aws_api_gateway_rest_api" "ca-gateway" {
  name        = "ca-gateway"
  description = "API Gateway for CA"
}

resource "aws_api_gateway_resource" "ca-proxy" {
  rest_api_id = aws_api_gateway_rest_api.ca-gateway.id
  parent_id   = aws_api_gateway_rest_api.ca-gateway.root_resource_id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "ca-proxy" {
  rest_api_id   = aws_api_gateway_rest_api.ca-gateway.id
  resource_id   = aws_api_gateway_resource.ca-proxy.id
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "ca-lambda" {
  rest_api_id = aws_api_gateway_rest_api.ca-gateway.id
  resource_id = aws_api_gateway_method.ca-proxy.resource_id
  http_method = aws_api_gateway_method.ca-proxy.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.ca.invoke_arn
}

resource "aws_api_gateway_method" "ca-proxy_root" {
  rest_api_id   = aws_api_gateway_rest_api.ca-gateway.id
  resource_id   = aws_api_gateway_rest_api.ca-gateway.root_resource_id
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "ca-lambda_root" {
  rest_api_id = aws_api_gateway_rest_api.ca-gateway.id
  resource_id = aws_api_gateway_method.ca-proxy_root.resource_id
  http_method = aws_api_gateway_method.ca-proxy_root.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.ca.invoke_arn
}

resource "aws_api_gateway_deployment" "ca" {
  depends_on = [
    aws_api_gateway_integration.ca-lambda,
    aws_api_gateway_integration.ca-lambda_root,
  ]

  rest_api_id = aws_api_gateway_rest_api.ca-gateway.id
  stage_name  = "live"
}

resource "aws_lambda_permission" "ca-apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ca.function_name
  principal     = "apigateway.amazonaws.com"

  # The "/*/*" portion grants access from any method on any resource
  # within the API Gateway REST API.
  source_arn = "${aws_api_gateway_rest_api.ca-gateway.execution_arn}/*/*"
}

output "ca_url" {
  value = "${aws_api_gateway_deployment.ca.invoke_url}"
}