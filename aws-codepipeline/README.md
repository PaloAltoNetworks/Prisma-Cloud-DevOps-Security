<h1>Overview</h1>


This extension enables Prisma Cloud Infrastructure-as-Code (IaC) scan and container image / serverless zip scan functionality from Palo Alto Networks Inc. in AWS Code Pipelines. Prisma Cloud IaC Scan identifies insecure configurations in common Infrastructure-as-Code (IaC) templates - for example, AWS Cloud Formation Templates, HashiCorp Terraform templates, Kubernetes App Deployment YAML files. More details about the functionality can be found here: https://docs.paloaltonetworks.com/prisma/prisma-cloud/prisma-cloud-admin/prisma-cloud-devops-security.html


  <h2>Prisma Cloud IaC Scan</h2>
  
    User can us this feature in 2 ways :
     1. Using AWS Lambda 
        OR
     2. Creating Custom action to run poll jobs (bash script) either in local enviornment or EC2 instance with AWS account.
     
     More Details on how to use it can be found in the documentation link:
      https://docs.paloaltonetworks.com/prisma/prisma-cloud/prisma-cloud-admin/prisma-cloud-devops-security/use-the-prisma-cloud-extension-for-aws-codepipeline.html
      
      
  <h2>Prisma Cloud Compute Image Scanning</h2>
    /buildspec.yml includes details on how to use twistcli when using AWS CodeBuild
