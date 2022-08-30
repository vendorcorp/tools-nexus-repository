# TOOLS: Nexus Repository Manager

This repository contains Terraform to build and manage our Nexus Repository Manager installation.

We are attempting to follow [the documented single node cloud AWS example](https://help.sonatype.com/repomanager3/planning-your-implementation/resiliency-and-high-availability/single-node-cloud-resilient-deployment-example-using-aws).

**A valid Sonatype License is required in this projects root directory named `sonatype-license.lic` for this code to work.**

## READ THIS FIRST

You need to have installed `aws-vault`, `aws-cli` and configured your access before you can run anything.

Read more here to understand how to do this.

The rest of this documentation assumes you have created an AWS Vault profile called `vendorcorp`.

## Technologies Used

- [Terraform](https://www.terraform.io/downloads.html) v1.0.11: What you'll find in this repository!
- AWS Vault: You need this to access Sonatype AWS Accounts

## Running Terraform

Use Terraform:
```
aws-vault exec vendorcorp -- terraform init
aws-vault exec vendorcorp -- terraform plan
aws-vault exec vendorcorp -- terraform apply
```

# The Fine Print

At the time of writing I work for Sonatype, and it is worth nothing that this is **NOT SUPPORTED** by Sonatype - it is purely a contribution to the open source community (read: you!).

Remember:
- Use this contribution at the risk tolerance that you have
- Do NOT file Sonatype support tickets related to cheque support in regard to this project
- DO file issues here on GitHub, so that the community can pitch in
