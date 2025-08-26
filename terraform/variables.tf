variable "control_plane_nodes" {
  description = "List of Kubernetes control plane nodes"
  type = list(object({
    name         = string
    server_type  = string
  }))
  default = []
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
