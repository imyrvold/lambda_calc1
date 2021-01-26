#!/bin/sh

FUNCTION_NAME=Calc
API_NAME=LambdaCalc
RESOURCE_NAME=calc
POLICY_NAME=lambda_execute
ROLE_NAME=lambda_invoke_function_assume_apigw_role
VALIDATE_REQUEST_PARAMETER_NAME=validate-request-parameters
REGION=eu-west-1
STAGE=test

function fail() {
    echo $2
    exit $1
}

echo "build lambda project..."
docker run \
    --rm \
    --volume "$(pwd)/:/src" \
    --workdir "/src/" \
    swift:5.3.2-amazonlinux2 \
    swift build --product calc -c release -Xswiftc -static-stdlib

echo "pack lambda.zip..."
scripts/package.sh ${RESOURCE_NAME}

echo "1 iam create-policy..."
aws iam create-policy \
    --policy-name $POLICY_NAME \
    --policy-document file://Invoke-Function-Role-Trust-Policy.json \
    > results/aws/create-policy.json

[ $? == 0 ] || fail 1 "Failed: AWS / iam / create-policy"

POLICY_ARN=$(aws iam list-policies --query "Policies[?PolicyName==\`${POLICY_NAME}\`].Arn" --output text --region ${REGION})

echo "2 iam create-role..."
aws iam create-role \
    --role-name $ROLE_NAME \
    --assume-role-policy-document file://Assume-STS-Role-Policy.json \
    > results/aws/create-role.json

[ $? == 0 ] || fail 2 "Failed: AWS / iam / create-role"

echo "3 iam attach-role-policy..."
aws iam attach-role-policy \
    --role-name $ROLE_NAME \
    --policy-arn $POLICY_ARN \
    > results/aws/attach-role-policy.json

[ $? == 0 ] || fail 3 "Failed: AWS / iam / attach-role-policy"

ROLE_ARN=$(aws iam list-roles --query "Roles[?RoleName==\`${ROLE_NAME}\`].Arn" --output text --region ${REGION})

sleep 10

echo "4 lambda create-function..."
aws lambda create-function \
    --region ${REGION} \
    --function-name ${FUNCTION_NAME} \
    --runtime provided.al2 \
    --handler lambda.run \
    --memory-size 128 \
    --zip-file fileb://.build/lambda/calc/lambda.zip \
    --role ${ROLE_ARN} \
    > results/aws/lambda-create-function.json

[ $? == 0 ] || fail 4 "Failed: AWS / lambda / create-function"

LAMBDA_ARN=$(aws lambda list-functions --query "Functions[?FunctionName==\`${FUNCTION_NAME}\`].FunctionArn" --output text --region ${REGION})

echo "5 apigateway create-rest-api..."
aws apigateway create-rest-api \
    --region ${REGION} \
    --name ${API_NAME} \
    --endpoint-configuration types=REGIONAL \
    > results/aws/create-rest-api.json

[ $? == 0 ] || fail 5 "Failed: AWS / apigateway / create-rest-api"

API_ID=$(aws apigateway get-rest-apis --query "items[?name==\`${API_NAME}\`].id" --output text --region ${REGION})
PARENT_RESOURCE_ID=$(aws apigateway get-resources --rest-api-id ${API_ID} --query 'items[?path==`/`].id' --output text --region ${REGION})

echo "6 apigateway create-resource..."
aws apigateway create-resource \
    --region ${REGION} \
    --rest-api-id ${API_ID} \
    --parent-id ${PARENT_RESOURCE_ID} \
    --path-part ${RESOURCE_NAME} \
    > results/aws/create-resource.json

[ $? == 0 ] || fail 6 "Failed: AWS / apigateway / create-resource"

RESOURCE_ID=$(aws apigateway get-resources --rest-api-id ${API_ID} --query "items[?path==\`/$RESOURCE_NAME\`].id" --output text --region ${REGION})

echo "7 apigateway create-request-validator..."
aws apigateway create-request-validator \
    --region ${REGION} \
    --rest-api-id ${API_ID} \
    --name ${VALIDATE_REQUEST_PARAMETER_NAME} \
    --validate-request-parameters \
    > results/aws/create-request-parameters-validator.json

[ $? == 0 ] || fail 7 "Failed: AWS / apigateway / create-request-validator"

REQUEST_VALIDATOR_PARAMETERS_ID=$(aws apigateway get-request-validators --rest-api-id ${API_ID} --query "items[?name==\`$VALIDATE_REQUEST_PARAMETER_NAME\`].id" --output text --region ${REGION})

#Integration 1
# Resources /calc/GET

echo "8 apigateway put-method..."
aws apigateway put-method \
    --region ${REGION} \
    --rest-api-id ${API_ID} \
    --resource-id ${RESOURCE_ID} \
    --http-method GET \
    --authorization-type NONE \
    --request-validator-id ${REQUEST_VALIDATOR_PARAMETERS_ID} \
    --request-parameters "method.request.querystring.operand1=true,method.request.querystring.operand2=true,method.request.querystring.operator=true" \
    > results/aws/put-get-method.json

[ $? == 0 ] || fail 8 "Failed: AWS / apigateway / put-method"

echo "9 apigateway put-method-response..."
aws apigateway put-method-response \
    --region ${REGION} \
    --rest-api-id ${API_ID} \
    --resource-id ${RESOURCE_ID} \
    --http-method GET \
    --status-code 200 \
    --response-models application/json=Empty \
    > results/aws/put-method-response.json

[ $? == 0 ] || fail 9 "Failed: AWS / apigateway / put-method-response"

echo "10 apigateway put-integration..."
aws apigateway put-integration \
    --region ${REGION} \
    --rest-api-id ${API_ID} \
    --resource-id ${RESOURCE_ID} \
    --http-method GET \
    --type AWS \
    --integration-http-method POST \
    --uri arn:aws:apigateway:${REGION}:lambda:path/2015-03-31/functions/${LAMBDA_ARN}/invocations \
    --credentials ${ROLE_ARN} \
    --passthrough-behavior WHEN_NO_TEMPLATES \
    --request-templates file://request-templates.json \
    > results/aws/put-get-integration.json

[ $? == 0 ] || fail 10 "Failed: AWS / apigateway / put-integration"

echo "11 apigateway put-integration-response..."
aws apigateway put-integration-response \
    --region ${REGION} \
    --rest-api-id ${API_ID} \
    --resource-id ${RESOURCE_ID} \
    --http-method GET \
    --status-code 200 \
    --response-templates application/json="" \
    > results/aws/put-get-integration-response.json

[ $? == 0 ] || fail 11 "Failed: AWS / apigateway / put-integration-response"

echo "12 apigateway create-deployment..."
aws apigateway create-deployment \
    --region ${REGION} \
    --rest-api-id ${API_ID} \
    --stage-name ${STAGE} \
    > results/aws/create-deployment.json

[ $? == 0 ] || fail 12 "Failed: AWS / apigateway / create-deployment"

ENDPOINT=https://${API_ID}.execute-api.eu-west-1.amazonaws.com/${STAGE}/calc
echo "API available at: ${ENDPOINT}"

echo
echo "Integration 1"
echo "Testing GET with query parameters:"
echo "27 / 9"
cat << EOF
curl -i --request GET \
https://${API_ID}.execute-api.eu-west-1.amazonaws.com/${STAGE}/calc\?operand1\=27\&operand2\=9\&operator\=div
EOF
echo

curl -i --request GET \
https://${API_ID}.execute-api.eu-west-1.amazonaws.com/${STAGE}/calc\?operand1\=27\&operand2\=9\&operator\=div