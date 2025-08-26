
resource "aws_key_pair" "key_pair" {
  key_name   = "khandle-cluster-nodes"
  public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPbIVEJOAcNCUTZXwK7GsN9HoPvLEUBFjm19zaLj7Tgh AWS khandle cluster nodes"
  tags = {
    Name    = "khandle-cluster-nodes"
    managed = "terraform"
  }
}

resource "aws_key_pair" "bastion_key_pair" {
  key_name   = "khandle-cluster-bastion"
  public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJGcwcFh8uDdVJRNXRgJJqSF+hQVtbJvofzDSuOh3sLf AWS khandle bastion node"
  tags = {
    Name    = "khandle-bastion"
    managed = "terraform"
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  filter {
    name   = "name"
    values = ["ubuntu/*/ubuntu-*-24.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "cloudinit_config" "instance_config" {
  gzip          = true
  base64_encode = true
  part {
    content_type = "text/cloud-config"
    content = templatefile("cloud-config.yaml", {})
  }
}

resource "aws_instance" "control_plane_node" {
  for_each = { for node in var.control_plane_nodes : node.name => node }

  ami                         = data.aws_ami.ubuntu.id
  instance_type               = each.value.server_type
  key_name                    = aws_key_pair.key_pair.key_name
  subnet_id                   = aws_subnet.subnet[0].id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.instance_security_group.id]
  user_data                   = data.cloudinit_config.instance_config.rendered
  tags = {
    Name         = "${each.key}"
    hostname     = "${each.key}"
  }
}

resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t3.micro"
  key_name                    = aws_key_pair.bastion_key_pair.key_name
  subnet_id                   = aws_subnet.subnet[0].id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.instance_security_group.id]
  user_data                   = data.cloudinit_config.instance_config.rendered
  tags = {
    Name         = "bastion"
    hostname     = "bastion"
  }
}





# ##### Elastic IP needs for initialisation of the instance

# # resource "aws_eip" "eip" {
# #   domain   = "vpc"
# #   tags = {
# #     Name    = "hassio"
# #     managed = "terraform"
# #   }
# # }

# # resource "aws_eip_association" "eip_association" {
# #   instance_id   = aws_instance.instance.id
# #   allocation_id = aws_eip.eip.id
# # }
