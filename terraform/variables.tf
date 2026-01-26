variable "control_plane_nodes" {
  description = "List of Kubernetes control plane nodes"
  type = list(object({
    name         = string
    server_type  = string
  }))
  default = []
}

variable "project_name" {
  default = "k8s-multi-cluster"
  type    = string
}

variable "common_tags" {
  default = {
    managed = "terraform"
    owner   = "andrey.vladimirskiy@piano.io"
  }
  type    = map(string)
}

# variable "route53_zone_id" {
#   description = "AWS Route53 Zone ID for the iodized.link zone"
#   default     = ""
#   type        = string
# }

# variable "route53_zone_name" {
#   default = ""
#   type    = string
# }

# variable "route53_record_name" {
#   default = ""
#   type    = string
# }
