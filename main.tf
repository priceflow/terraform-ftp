provider "aws" {
  region = "us-west-2"
}

terraform {
  backend "s3" {}
}

data "terraform_remote_state" "vpc" {
  backend = "s3"

  config {
    bucket = "${var.remote_bucket}"
    key    = "vpc/terraform.tfstate"
    region = "us-west-2"
  }
}

# FTP server
data "template_file" "user_data" {
  template = "${file("${path.module}/user_data.sh")}"

  vars {
    user_data = "${join("\n", var.user_data)}"
    ssh_user  = "${var.ssh_user}"
  }
}

data "aws_iam_policy_document" "default" {
  statement {
    sid = ""

    actions = [
      "sts:AssumeRole",
    ]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    effect = "Allow"
  }
}

resource "aws_iam_instance_profile" "default" {
  name = "${var.name}"
  role = "${aws_iam_role.default.name}"
}

resource "aws_iam_role" "default" {
  name = "${var.name}"
  path = "/"

  assume_role_policy = "${data.aws_iam_policy_document.default.json}"
}

resource "aws_security_group" "default" {
  name        = "${var.name}"
  vpc_id      = "${data.terraform_remote_state.vpc.vpc_id}"
  description = "Lambda FTP security group - only allow ingress from VPC"

  ingress {
    protocol  = "tcp"
    from_port = 20
    to_port   = 22

    cidr_blocks = ["${var.allowed_cidr_blocks}"]
  }

  ingress {
    protocol  = "tcp"
    from_port = 10000
    to_port   = 10100

    cidr_blocks = ["${var.allowed_cidr_blocks}"]
  }

  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = -1
    security_groups = ["${data.terraform_remote_state.vpc.default_security_group_id}"]
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_instance" "default" {
  ami           = "${var.ami}"
  instance_type = "${var.instance_type}"

  user_data = "${data.template_file.user_data.rendered}"

  vpc_security_group_ids = [
    "${compact(concat(list(aws_security_group.default.id), list(data.terraform_remote_state.vpc.default_security_group_id)))}",
  ]

  iam_instance_profile        = "${aws_iam_instance_profile.default.name}"
  associate_public_ip_address = "true"

  key_name = "${var.key_name}"

  subnet_id = "${data.terraform_remote_state.vpc.private_subnets[0]}"

  tags = "${merge(map("Name", format("%s", var.name)), var.tags)}"
}
