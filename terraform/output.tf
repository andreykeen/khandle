# output "availability_zones" {
#   value = data.aws_availability_zones.available
# }

# output "aws_subnet" {
#   value = aws_subnet.subnet
# }

# output "aws_ami" {
#   value = data.aws_ami.ubuntu
# }

# output "acm_certificate" {
#   value = aws_acm_certificate_validation.acm_certificate_validation.certificate_arn
# }

# output "lb_web_target_group" {
#   value = aws_lb_target_group.lb_web_target_group
# }

# output "load_balancer" {
#   value = aws_lb.load_balancer
# }


output "control_plane_nodes" {
  value = {
    for k, v in aws_instance.control_plane_node : k => {
      public_ip  = v.public_ip
      private_ip = v.private_ip
    }
  }
}
