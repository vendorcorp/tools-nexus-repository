variable "aws_region" {
  description = "AWS Region that our deployment is targetting"
  type        = string
  default     = "us-east-2"
}

variable "default_resource_tags" {
  description = "List of tags to apply to all resources created in AWS"
  type        = map(string)
  default = {
    environment : "development"
    purpose : "vendorcorp"
    owner : "phorton@sonatype.com"
    sonatype-group : "se"
    vendorcorp-purpose : "tools"
  }
}

# See https://docs.sonatype.com/display/OPS/Shared+Infrastructure+Initiative
variable "environment" {
  description = "Used as part of Sonatype's Shared AWS Infrastructure"
  type        = string
  default     = "production"
}

variable "target_namespace" {
  description = "Namespace to create and deploy Nexus Repository Manager into."
  type        = string
  default     = "tools-nexus-repository"
}

variable "nxrm_instance_purpose" {
  description = "Purpose of this NXRM installation - i.e. Vendor Corp, or other."
  type        = string
  default     = "vendorcorp"
  validation {
    condition     = contains(["se", "vendorcorp"], var.nxrm_instance_purpose)
    error_message = "Valid values for var: nxrm_instance_purpose are (se, vendorcorp)."
  }
}

variable "pgsql_password" {
  description = "Password for the main account in PostgreSQL Cluster"
  type        = string
  sensitive   = true
  validation {
    condition     = length(var.pgsql_password) > 0
    error_message = "PostgreSQL password must be supplied."
  }
}
