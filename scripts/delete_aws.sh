#!/bin/sh

FUNCTION_NAME=Calc
API_NAME=LambdaCalc
POLICY_NAME=lambda_execute
ROLE_NAME=lambda_invoke_function_assume_apigw_role
REGION=eu-west-1

POLICY_ARN=$(aws iam list-policies --query "Policies[?PolicyName==\`${POLICY_NAME}\`].Arn" --output text --region ${REGION})

aws iam detach-role-policy \
        --role-name $ROLE_NAME \
        --policy-arn $POLICY_ARN

aws iam delete-policy \
    --policy-arn $POLICY_ARN

aws iam delete-role \
    --role-name $ROLE_NAME

API_ID=$(aws apigateway get-rest-apis --query "items[?name==\`${API_NAME}\`].id" --output text --region ${REGION})

aws apigateway delete-rest-api \
    --rest-api-id ${API_ID}

aws lambda delete-function \
    --function-name $FUNCTION_NAME

