
# resource "aws_lb" "load_balancer" {
#   name                       = "ha-lb"
#   internal                   = false
#   load_balancer_type         = "network"
#   security_groups            = [aws_security_group.lb_security_group.id]
#   subnets                    = [aws_subnet.subnet[0].id]
#   enable_deletion_protection = false
#   tags = {
#     Name        = "hassio"
#     Environment = "production"
#   }
# }


# ##### Target and Listener for SSH

# resource "aws_lb_target_group" "lb_ssh_target_group" {
#   name     = "ha-lb-ssh-target-group"
#   port     = 22
#   protocol = "TCP"
#   vpc_id   = aws_vpc.vpc.id
# }

# resource "aws_lb_target_group_attachment" "lb_ssh_target_group_attachment" {
#   target_group_arn = aws_lb_target_group.lb_ssh_target_group.arn
#   target_id        = aws_instance.instance.id
#   port             = 22
# }

# resource "aws_lb_listener" "lb_ssh_listener" {
#   load_balancer_arn = aws_lb.load_balancer.arn
#   port              = "22"
#   protocol          = "TCP"
#   default_action {
#     type             = "forward"
#     target_group_arn = aws_lb_target_group.lb_ssh_target_group.arn
#   }
# }


# ##### Target and Listener for WEB

# resource "aws_lb_target_group" "lb_web_target_group" {
#   name     = "ha-lb-web-target-group"
#   port     = 80
#   protocol = "TCP"
#   vpc_id   = aws_vpc.vpc.id
#   health_check {
#     port = 22
#     protocol = "TCP"
#   }
# }

# resource "aws_lb_target_group_attachment" "lb_web_target_group_attachment" {
#   target_group_arn = aws_lb_target_group.lb_web_target_group.arn
#   target_id        = aws_instance.instance.id
#   port             = 80
# }

# resource "aws_lb_listener" "lb_web_listener" {
#   load_balancer_arn = aws_lb.load_balancer.arn
#   port              = "443"
#   protocol          = "TLS"
#   ssl_policy        = "ELBSecurityPolicy-2016-08"
#   certificate_arn   = aws_acm_certificate_validation.acm_certificate_validation.certificate_arn
#   default_action {
#     type             = "forward"
#     target_group_arn = aws_lb_target_group.lb_web_target_group.arn
#   }
# }


# ##### Target and Listener for UDP WireGuard

# resource "aws_lb_target_group" "lb_udp_target_group" {
#   name     = "ha-lb-udp-target-group"
#   port     = 51820
#   protocol = "UDP"
#   vpc_id   = aws_vpc.vpc.id
# }

# resource "aws_lb_target_group_attachment" "lb_udp_target_group_attachment" {
#   target_group_arn = aws_lb_target_group.lb_udp_target_group.arn
#   target_id        = aws_instance.instance.id
#   port             = 51820
# }

# resource "aws_lb_listener" "lb_udp_listener" {
#   load_balancer_arn = aws_lb.load_balancer.arn
#   port              = "51820"
#   protocol          = "UDP"
#   default_action {
#     type             = "forward"
#     target_group_arn = aws_lb_target_group.lb_udp_target_group.arn
#   }
# }


# ##### Creating CNAME record with Load balancer target

# resource "aws_route53_record" "lb_route53_record" {
#   zone_id = var.route53_zone_id
#   name    = "${var.route53_record_name}.${var.route53_zone_name}"
#   records = [aws_lb.load_balancer.dns_name]
#   ttl     = 60
#   type    = "CNAME"
# }
