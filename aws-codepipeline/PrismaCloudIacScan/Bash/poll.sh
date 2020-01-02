#!/bin/bash 

set -u
set -e
trap "echo ERR;   exit" ERR

# exec &> >(while read line; do echo "$(date +'%h %d %H:%M:%S') $line" >> cmds.log; done;)

#set -x

if [[ -z "${1:-}" ]]; then
  echo "Usage: ./poll.sh <action type id>" >&2
  echo -e "Example:\n  ./poll.sh \"category=Test,owner=Custom,version=1,provider=Prisma-Cloud-IaC-Scan\"" >&2
  exit 1
fi

echo_ts() {
  
  echo -e "\n" >> Prisma_Cloud_IaC_Scan.log
  echo "$1" >> Prisma_Cloud_IaC_Scan.log
 
}

run() {

  local action_type_id="$1"
  echo_ts "actiontypeid: $action_type_id"

  #while :
  #do
    local job_json="$(fetch_job "$action_type_id")"

      if [[ "$job_json" != "null"  && "$job_json" != "None" && "$job_json" != "" ]]; then
        
        local job_id="$(echo "$job_json" | jq -r '.id')"
        echo "job_id: $job_id"
        mkdir $job_id
        chmod +x $job_id
        cd $job_id || update_job_status "$job_json" "job id not found"
        
        acknowledge_job "$job_json"
        local build_json=$(create_build "$job_json")
      else
          sleep 10   
      fi
   #done   
}
acknowledge_job() {

  local job_json="$1"
  local job_id="$(echo "$job_json" | jq -r '.id')"
  local nonce="$(echo "$job_json" | jq -r '.nonce')"

  echo_ts "Acknowledging CodePipeline job  (id: $job_id nonce: $nonce)" >&2

  aws codepipeline acknowledge-job --job-id "$job_id" --nonce "$nonce" > /dev/null 2>&1
}

fetch_job() {

  local action_type_id="$1"

  aws codepipeline poll-for-jobs --max-batch-size 1 \
                                 --action-type-id "$action_type_id" \
                                 --query 'jobs[0]'
}

action_configuration_value() {

  local job_json="$1"
  local configuration_key="$2"
 
  echo "$job_json" | jq -r ".data.actionConfiguration.configuration | .[\"$configuration_key\"]"

}

update_job_status() {
  local job_json="$1"
  local build_state="$2"

  local job_id="$(echo "$job_json" | jq -r '.id')"

  echo_ts "Updating CodePipeline job with '$build_state' and job_id '$job_id'result" >&2
  
  if [[ "$build_state" == "success" ]]; then
    aws codepipeline put-job-success-result \
      --job-id "$job_id" \
      --execution-details "summary=Build succeeded,externalExecutionId=$job_id,percentComplete=100"
  else
    aws codepipeline put-job-failure-result \
      --job-id "$job_id" \
      --failure-details "type=JobFailed,message=Build $build_state,externalExecutionId=$job_id"
  fi
}


decide_job_status(){
      local job_json="$1"
      local stats="$2"
      local in_high="$(echo "$job_json" | jq -r ".data.actionConfiguration.configuration.FailureCriteria_HighSeverity")" 
      local in_med="$(echo "$job_json" | jq -r ".data.actionConfiguration.configuration.FailureCriteriaMediumSeverity")"
      local in_low="$(echo "$job_json" | jq -r ".data.actionConfiguration.configuration.FailureCriteriaLowSeverity")"
      local in_oper="$(echo "$job_json" | jq -r ".data.actionConfiguration.configuration.FailureCriteriaOperator")"

      local resp_high="$(echo "$stats" | jq -r '.high')"
      local resp_med="$(echo "$stats" | jq -r '.medium')"
      local resp_low="$(echo "$stats" | jq -r '.low')"
      

      if [[ $in_oper == null ]];then
          in_oper="or"
      fi
      if [[ $in_high == null ]];then
        in_high=0
      fi
      if [[ $in_med == null ]];then
        in_med=0
      fi
      if [[ $in_low == null ]];then
        in_low=0
      fi
      
      if [[ $stats != null ]] ;then
            if [[ "$in_oper" == "or" && ( "$resp_high" -ge "$in_high" || "$resp_med" -ge "$in_med" || "$resp_low" -ge "$in_low"  ) ]] ;then
                echo_ts "Prisma Cloud IaC scan failed with issues as security issues count (High: $resp_high, Medium: $resp_med, Low: $resp_low) meets or exceeds failure criteria (High: $in_high, Medium: $in_med, Low: $in_low)"
                update_job_status "$job_json" "failure"
            
            elif [[ "$in_oper" == "and" && ( "$resp_high" -ge "$in_high" && "$resp_med" -ge "$in_med" && "$resp_low" -ge "$in_low" ) ]]; then
               echo_ts "Prisma Cloud IaC scan failed with issues as security issues count (High: $resp_high, Medium: $resp_med, Low: $resp_low) meets or exceeds failure criteria (High: $in_high, Medium: $in_med, Low: $in_low)"
               update_job_status "$job_json" "failure"
            
            else
                echo_ts "Prisma Cloud IaC scan succeeded with issues as security issues count (High: $resp_high, Medium: $resp_med, Low: $resp_low) does not exceed failure criteria (High: $in_high, Medium: $in_med, Low: $in_low)"
                update_job_status "$job_json" "success"
            fi
      
      else
         update_job_status "$job_json" "success"
      fi   
     
}

create_build() {
  
  local job_json="$1"
  local job_id="$(echo "$job_json" | jq -r '.id')"
  local s3_bucket=$(action_configuration_value "$job_json" "S3BucketName")
  local bucketName="$(echo "$job_json" | jq -r ".data.inputArtifacts[0].location.s3Location | .[\"bucketName\"]")"
  local object_key="$(echo "$job_json" | jq -r ".data.inputArtifacts[0].location.s3Location | .[\"objectKey\"]")"
  local output_object="$(echo "$job_json" | jq -r ".data.outputArtifacts[0].location.s3Location | .[\"objectKey\"]")"

  local console_url="$(echo "$job_json" | jq -r ".data.actionConfiguration.configuration.Prisma_Cloud_API_URL")"
  local access_key="$(echo "$job_json" | jq -r ".data.actionConfiguration.configuration.Access_Key")"
  local secret_key="$(echo "$job_json" | jq -r ".data.actionConfiguration.configuration.Secret_Key")"
 

  if [ -z "$console_url" ]; then
    echo_ts "Please enter valid Prisma Cloud API URL in plugin in Input param. For details refer to :plugin link"
    update_job_status "$job_json" "Please enter valid Prisma Cloud API URL in plugin in Input param. For details refer to plugin link"
    exit 1;
  fi

  local login_url="${console_url}/login"
  
  local req_cmd=$(curl -k -i -o -X POST  $login_url -H "Content-Type:application/json" -d "{\"username\":\"${access_key}\",\"password\":\"${secret_key}\"}"  ) || update_job_status "$job_json" "$err_500"
  
  local err_400="Invalid credentials please verify that API URL, Access Key and Secret Key in Prisma Cloud plugin settings are valid For details refer to Extension link  https://docs.paloaltonetworks.com/prisma/prisma-cloud/prisma-cloud-admin/prisma-cloud-devops-security/use-the-prisma-cloud-extension-for-aws-codepipeline.html"
  local err_500="Oops! Something went wrong, please try again or refer to documentation on https://docs.paloaltonetworks.com/prisma/prisma-cloud/prisma-cloud-admin/prisma-cloud-devops-security/use-the-prisma-cloud-extension-for-aws-codepipeline.html"
  
  http_status=$(echo "$req_cmd" | grep HTTP |  awk '{print $2}')

  if [ -z "$http_status" ]; then
    echo_ts '$err_500' >&2
    update_job_status "$job_json" "error"
    exit 1;
  fi 

  if [[ "$http_status" == 400 || "$http_status" == 401 ]] ; then
      echo_ts '$err_400' >&2
      update_job_status "$job_json" "error"
      exit 1
      
  fi 

  if [[ $http_status -ge 500 ]] ; then
    echo_ts '$err_500' >&2
    update_job_status "$job_json" "error"
    exit 1
  fi  
  
  output_response=$(echo "$req_cmd" | grep token)
  
  local token="$(echo "$output_response" | jq  .token | tr -d '"')"
  
 
  local scan_location="$(echo $bucketName/$object_key)"

  aws s3 cp s3://$scan_location . || update_job_status "$job_json" "Copy Object from S3 bucket failed"
 
  
  local file=( *.zip )
  
  mv $file artifact.zip
  
  iacAPI=${console_url}/iac_scan
 
  while :
  do
   
   local response="$(curl -k  -X POST $iacAPI -H "x-redlock-auth:${token}" -F templateFile=@artifact.zip)" || update_job_status "$job_json" "Call from API failed"
  
   local result="$(echo "$response" | jq -r '.result.is_successful')"

   if [[ $result ]]
   then
     local matched="$(echo "$response" | jq -r '.result.rules_matched')"

     if [[ $matched != null ]] ;then

        local stats="$(echo "$response" | jq -r '.result.severity_stats')"
   
        display="$(echo "$matched" | jq -r 'sort_by(.severity) | (["SEVERITY" ,"NAME" ,"FILES"]  | (., map(length*"-")) ), (.[]  | [.severity , .name, .files[0] ])  | join(",")' | column -t -s ",")" || update_job_status "$job_json" "Unknown Error "
       
     else
       echo_ts "Good job! Prisma Cloud did not detect any issues."

    fi
  fi
   
   if [[ "$result" != "null" ]]; then
      
      if [[ $result == "true"  ]] ;then
          decide_job_status "$job_json" "$stats"
       
      fi
      break  
    else
       echo_ts "Build is running" 
       sleep 3
    fi
  done

  echo_ts "$display" >&2
  
  aws s3 cp Prisma_Cloud_IaC_Scan.log  s3://$s3_bucket/Prisma_Cloud_IaC_Scan_$job_id.log || update_job_status "$job_json" "upload results to S3 bucket failed"
 
  cd .. 
  rm -fr $job_id 

}

run "$1"
